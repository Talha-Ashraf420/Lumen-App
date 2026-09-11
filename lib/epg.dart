import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:xml/xml.dart';
import 'package:xml/xml_events.dart';

/// Normalized programme metadata shared by Xtream and XMLTV sources.
///
/// All times are UTC and [stopUtc] is exclusive. Provider credentials and
/// playback URLs deliberately do not belong in this model.
class EpgProgramme {
  const EpgProgramme({
    required this.channelKey,
    required this.startUtc,
    required this.stopUtc,
    required this.title,
    this.subtitle = '',
    this.description = '',
    this.categories = const [],
    this.icon = '',
    this.hasArchive = false,
    this.catchupId = '',
    this.stopInferred = false,
  });

  final String channelKey;
  final DateTime startUtc;
  final DateTime stopUtc;
  final String title;
  final String subtitle;
  final String description;
  final List<String> categories;
  final String icon;
  final bool hasArchive;
  final String catchupId;
  final bool stopInferred;

  Duration get duration => stopUtc.difference(startUtc);

  bool overlaps(DateTime start, DateTime end) =>
      startUtc.isBefore(end) && stopUtc.isAfter(start);

  EpgProgramme copyWith({DateTime? stopUtc, bool? stopInferred}) =>
      EpgProgramme(
        channelKey: channelKey,
        startUtc: startUtc,
        stopUtc: stopUtc ?? this.stopUtc,
        title: title,
        subtitle: subtitle,
        description: description,
        categories: categories,
        icon: icon,
        hasArchive: hasArchive,
        catchupId: catchupId,
        stopInferred: stopInferred ?? this.stopInferred,
      );
}

class EpgChannel {
  const EpgChannel({
    required this.channelKey,
    this.displayNames = const [],
    this.icon = '',
  });

  final String channelKey;
  final List<String> displayNames;
  final String icon;
}

class EpgParseSummary {
  const EpgParseSummary({
    required this.channelCount,
    required this.programmeCount,
    required this.storedProgrammeCount,
    required this.compressedBytes,
    required this.decompressedBytes,
  });

  final int channelCount;
  final int programmeCount;
  final int storedProgrammeCount;
  final int compressedBytes;
  final int decompressedBytes;
}

class EpgSourceState {
  const EpgSourceState({
    required this.sourceKey,
    required this.activeGeneration,
    required this.status,
    required this.fetchedAt,
    this.etag = '',
    this.lastModified = '',
    this.validFrom,
    this.validUntil,
    this.lastError = '',
    this.nextRetryAt,
  });

  final String sourceKey;
  final int activeGeneration;
  final String status;
  final DateTime fetchedAt;
  final String etag;
  final String lastModified;
  final DateTime? validFrom;
  final DateTime? validUntil;
  final String lastError;
  final DateTime? nextRetryAt;
}

class EpgParseException implements Exception {
  const EpgParseException(this.message);

  final String message;

  @override
  String toString() => message;
}

typedef EpgChannelBatchSink = FutureOr<void> Function(List<EpgChannel> batch);
typedef EpgProgrammeBatchSink =
    FutureOr<void> Function(List<EpgProgramme> batch);

/// Incremental XMLTV parser with explicit resource guards.
///
/// It builds at most one `<channel>` or `<programme>` subtree at a time and
/// emits bounded batches. Large guides therefore do not become one giant XML
/// DOM or one giant Dart object list.
class EpgXmltvParser {
  const EpgXmltvParser({
    this.maxCompressedBytes = 50 * 1024 * 1024,
    this.maxDecompressedBytes = 250 * 1024 * 1024,
    this.maxProgrammes = 200000,
    this.channelBatchSize = 100,
    this.programmeBatchSize = 500,
  });

  final int maxCompressedBytes;
  final int maxDecompressedBytes;
  final int maxProgrammes;
  final int channelBatchSize;
  final int programmeBatchSize;

  Future<EpgParseSummary> parse(
    Stream<List<int>> input, {
    DateTime? windowStartUtc,
    DateTime? windowEndUtc,
    EpgChannelBatchSink? onChannels,
    EpgProgrammeBatchSink? onProgrammes,
  }) async {
    if (windowStartUtc != null &&
        windowEndUtc != null &&
        !windowStartUtc.isBefore(windowEndUtc)) {
      throw const EpgParseException('The EPG time window is invalid.');
    }

    var compressedBytes = 0;
    var decompressedBytes = 0;
    final bytes = _decodeGzipIfPresent(
      input,
      maxCompressedBytes: maxCompressedBytes,
      maxDecompressedBytes: maxDecompressedBytes,
      onCompressedCount: (count) => compressedBytes = count,
      onDecompressedCount: (count) => decompressedBytes = count,
    );

    final channels = <EpgChannel>[];
    final programmes = <EpgProgramme>[];
    final pendingStops = <String, EpgProgramme>{};
    var channelCount = 0;
    var programmeCount = 0;
    var storedProgrammeCount = 0;

    Future<void> flushChannels() async {
      if (channels.isEmpty || onChannels == null) {
        channels.clear();
        return;
      }
      final batch = List<EpgChannel>.unmodifiable(channels);
      channels.clear();
      await onChannels(batch);
    }

    Future<void> flushProgrammes() async {
      if (programmes.isEmpty || onProgrammes == null) {
        programmes.clear();
        return;
      }
      final batch = List<EpgProgramme>.unmodifiable(programmes);
      programmes.clear();
      await onProgrammes(batch);
    }

    bool inWindow(EpgProgramme programme) {
      final start = windowStartUtc;
      final end = windowEndUtc;
      if (start == null || end == null) return true;
      return programme.overlaps(start, end);
    }

    Future<void> emitProgramme(EpgProgramme programme) async {
      if (!inWindow(programme)) return;
      programmes.add(programme);
      storedProgrammeCount++;
      if (programmes.length >= programmeBatchSize) await flushProgrammes();
    }

    try {
      final strings = utf8.decoder.bind(bytes);
      final nodes = strings
          .toXmlEvents(validateNesting: true)
          .normalizeEvents()
          .selectSubtreeEvents(
            (event) => event.name == 'channel' || event.name == 'programme',
          )
          .toXmlNodes();

      await for (final chunk in nodes) {
        for (final node in chunk.whereType<XmlElement>()) {
          if (node.name.local == 'channel') {
            final channel = _parseXmltvChannel(node);
            if (channel == null) continue;
            channels.add(channel);
            channelCount++;
            if (channels.length >= channelBatchSize) await flushChannels();
            continue;
          }
          if (node.name.local != 'programme') continue;
          programmeCount++;
          if (programmeCount > maxProgrammes) {
            throw EpgParseException(
              'The EPG contains more than $maxProgrammes programmes.',
            );
          }
          final programme = _parseXmltvProgramme(node);
          if (programme == null) continue;

          final pending = pendingStops.remove(programme.channelKey);
          if (pending != null) {
            final inferredStop = programme.startUtc.isAfter(pending.startUtc)
                ? programme.startUtc
                : pending.startUtc.add(const Duration(minutes: 30));
            await emitProgramme(
              pending.copyWith(stopUtc: inferredStop, stopInferred: true),
            );
          }

          if (programme.stopInferred) {
            pendingStops[programme.channelKey] = programme;
          } else {
            await emitProgramme(programme);
          }
        }
      }

      for (final pending in pendingStops.values) {
        await emitProgramme(
          pending.copyWith(
            stopUtc: pending.startUtc.add(const Duration(minutes: 30)),
            stopInferred: true,
          ),
        );
      }
      await flushChannels();
      await flushProgrammes();
    } on EpgParseException {
      rethrow;
    } catch (_) {
      // Parser and transport exceptions can include request data. Keep the
      // public/storage-safe error deliberately generic.
      throw const EpgParseException('The provider returned malformed XMLTV.');
    }

    return EpgParseSummary(
      channelCount: channelCount,
      programmeCount: programmeCount,
      storedProgrammeCount: storedProgrammeCount,
      compressedBytes: compressedBytes,
      decompressedBytes: decompressedBytes,
    );
  }
}

/// Decode gzip only when the actual payload has the gzip magic bytes.
///
/// `dart:io` can transparently decompress HTTP responses while preserving the
/// original Content-Encoding header. Looking at both the hint and the bytes
/// prevents a second, invalid decompression in that case and also accepts
/// providers that send gzip without a useful header.
Stream<List<int>> _decodeGzipIfPresent(
  Stream<List<int>> input, {
  required int maxCompressedBytes,
  required int maxDecompressedBytes,
  required void Function(int count) onCompressedCount,
  required void Function(int count) onDecompressedCount,
}) async* {
  final iterator = StreamIterator<List<int>>(input);
  final prefix = <int>[];
  try {
    while (prefix.length < 2 && await iterator.moveNext()) {
      prefix.addAll(iterator.current);
    }
    if (prefix.isEmpty) return;

    final hasGzipSignature =
        prefix.length >= 2 && prefix[0] == 0x1f && prefix[1] == 0x8b;
    var rawCount = 0;
    Stream<List<int>> guardedInput() async* {
      void count(List<int> chunk) {
        rawCount += chunk.length;
        onCompressedCount(rawCount);
        final rawLimit = hasGzipSignature
            ? maxCompressedBytes
            : maxDecompressedBytes;
        if (rawCount > rawLimit) {
          throw EpgParseException(
            hasGzipSignature
                ? 'The compressed EPG exceeds the safety limit.'
                : 'The expanded EPG exceeds the safety limit.',
          );
        }
      }

      count(prefix);
      yield prefix;
      while (await iterator.moveNext()) {
        final chunk = iterator.current;
        count(chunk);
        yield chunk;
      }
    }

    // The payload signature is authoritative because dart:io may already have
    // expanded a response whose HTTP headers still say gzip.
    final decoded = hasGzipSignature
        ? gzip.decoder.bind(guardedInput())
        : guardedInput();
    var decodedCount = 0;
    await for (final chunk in decoded) {
      decodedCount += chunk.length;
      onDecompressedCount(decodedCount);
      if (decodedCount > maxDecompressedBytes) {
        throw const EpgParseException(
          'The expanded EPG exceeds the safety limit.',
        );
      }
      yield chunk;
    }
  } finally {
    await iterator.cancel();
  }
}

EpgChannel? _parseXmltvChannel(XmlElement node) {
  final key = (node.getAttribute('id') ?? '').trim();
  if (key.isEmpty) return null;
  final names = node
      .findElements('display-name')
      .map((element) => element.innerText.trim())
      .where((value) => value.isNotEmpty)
      .toSet()
      .toList(growable: false);
  final icon = node.findElements('icon').firstOrNull?.getAttribute('src') ?? '';
  return EpgChannel(channelKey: key, displayNames: names, icon: icon.trim());
}

EpgProgramme? _parseXmltvProgramme(XmlElement node) {
  final channelKey = (node.getAttribute('channel') ?? '').trim();
  final start = parseXmltvTimestamp(node.getAttribute('start') ?? '');
  if (channelKey.isEmpty || start == null) return null;
  final parsedStop = parseXmltvTimestamp(node.getAttribute('stop') ?? '');
  final stop = parsedStop != null && parsedStop.isAfter(start)
      ? parsedStop
      : start.add(const Duration(minutes: 30));
  final title = _firstText(node, 'title');
  final categories = node
      .findElements('category')
      .map((element) => element.innerText.trim())
      .where((value) => value.isNotEmpty)
      .toSet()
      .toList(growable: false);
  return EpgProgramme(
    channelKey: channelKey,
    startUtc: start,
    stopUtc: stop,
    title: title.isEmpty ? 'Programming information unavailable' : title,
    subtitle: _firstText(node, 'sub-title'),
    description: _firstText(node, 'desc'),
    categories: categories,
    icon: (node.findElements('icon').firstOrNull?.getAttribute('src') ?? '')
        .trim(),
    stopInferred: parsedStop == null || !parsedStop.isAfter(start),
  );
}

String _firstText(XmlElement parent, String name) =>
    parent.findElements(name).firstOrNull?.innerText.trim() ?? '';

/// Parse XMLTV's compact timestamp format into UTC.
///
/// Examples: `20260912153000 +0500`, `20260912103000Z`, or a timestamp
/// without a zone (which XMLTV defines as UTC).
DateTime? parseXmltvTimestamp(String raw) {
  final match = RegExp(
    r'^\s*(\d{4})(\d{2})(\d{2})(?:(\d{2})(\d{2})(\d{2})?)?\s*(Z|[+-]\d{2}:?\d{2})?\s*$',
  ).firstMatch(raw);
  if (match == null) return null;
  try {
    final year = int.parse(match.group(1)!);
    final month = int.parse(match.group(2)!);
    final day = int.parse(match.group(3)!);
    final hour = int.tryParse(match.group(4) ?? '') ?? 0;
    final minute = int.tryParse(match.group(5) ?? '') ?? 0;
    final second = int.tryParse(match.group(6) ?? '') ?? 0;
    if (hour > 23 || minute > 59 || second > 59) return null;
    var result = DateTime.utc(year, month, day, hour, minute, second);
    if (result.year != year || result.month != month || result.day != day) {
      return null;
    }
    final zone = match.group(7);
    if (zone != null && zone != 'Z') {
      final compact = zone.replaceAll(':', '');
      final sign = compact.startsWith('-') ? -1 : 1;
      final hours = int.parse(compact.substring(1, 3));
      final minutes = int.parse(compact.substring(3, 5));
      if (hours > 23 || minutes > 59) return null;
      result = result.subtract(
        Duration(minutes: sign * (hours * 60 + minutes)),
      );
    }
    return result;
  } catch (_) {
    return null;
  }
}

/// Normalize a `get_short_epg` or `get_simple_data_table` response.
List<EpgProgramme> parseXtreamEpg(
  dynamic payload, {
  required String fallbackChannelKey,
}) {
  final rawListings = payload is Map ? payload['epg_listings'] : payload;
  if (rawListings is! List) return const [];
  final result = <EpgProgramme>[];
  for (final raw in rawListings.whereType<Map>()) {
    final row = raw.cast<dynamic, dynamic>();
    final start = _xtreamTime(row['start_timestamp'] ?? row['start']);
    final stop = _xtreamTime(row['stop_timestamp'] ?? row['end']);
    if (start == null || stop == null || !stop.isAfter(start)) continue;
    result.add(
      EpgProgramme(
        channelKey:
            '${row['channel_id'] ?? row['epg_id'] ?? fallbackChannelKey}'
                .trim(),
        startUtc: start,
        stopUtc: stop,
        title: _decodeXtreamText(row['title'], fallback: 'Untitled programme'),
        description: _decodeXtreamText(row['description']),
        hasArchive: _truthy(row['has_archive']),
        catchupId: '${row['id'] ?? ''}'.trim(),
      ),
    );
  }
  result.sort((a, b) => a.startUtc.compareTo(b.startUtc));
  return List.unmodifiable(result);
}

DateTime? _xtreamTime(dynamic value) {
  if (value is num) {
    final number = value.toInt();
    final millis = number.abs() < 100000000000 ? number * 1000 : number;
    return DateTime.fromMillisecondsSinceEpoch(millis, isUtc: true);
  }
  final text = '$value'.trim();
  final number = int.tryParse(text);
  if (number != null) return _xtreamTime(number);
  final parsed = DateTime.tryParse(text.replaceFirst(' ', 'T'));
  return parsed?.toUtc();
}

String _decodeXtreamText(dynamic value, {String fallback = ''}) {
  final text = '$value'.trim();
  if (text.isEmpty || text == 'null') return fallback;
  if (!RegExp(r'^[A-Za-z0-9+/]+={0,2}$').hasMatch(text) ||
      text.length % 4 != 0) {
    return text;
  }
  try {
    final decoded = utf8.decode(base64.decode(text));
    final printable = decoded.runes.where((rune) => rune >= 32).length;
    if (decoded.isNotEmpty &&
        printable / math.max(decoded.runes.length, 1) > .8) {
      return decoded.trim();
    }
  } catch (_) {}
  return text;
}

bool _truthy(dynamic value) =>
    value == true ||
    value == 1 ||
    '$value' == '1' ||
    '$value'.toLowerCase() == 'true';
