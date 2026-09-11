import 'dart:async';
import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;

import 'catalog_store.dart';
import 'epg.dart';

class EpgSyncException implements Exception {
  const EpgSyncException(this.message);

  final String message;

  @override
  String toString() => message;
}

class EpgSyncResult {
  const EpgSyncResult({
    required this.notModified,
    required this.sourceKey,
    this.summary,
  });

  final bool notModified;
  final String sourceKey;
  final EpgParseSummary? summary;
}

/// Stable non-reversible source identity safe for SQLite and diagnostics.
///
/// The full URI may contain IPTV credentials, so it must never be persisted or
/// included in errors. Profile scope still provides the account boundary.
String epgSourceKey(Uri uri) =>
    sha256.convert(utf8.encode(uri.toString())).toString();

/// Downloads an XMLTV guide into a staged SQLite generation.
///
/// A completed parse atomically activates the generation. Failed or cancelled
/// work is removed and cannot replace the last successful guide.
class EpgXmltvLoader {
  EpgXmltvLoader({
    required http.Client httpClient,
    CatalogStore? store,
    EpgXmltvParser parser = const EpgXmltvParser(),
  }) : _http = httpClient,
       _store = store ?? CatalogStore.instance,
       _parser = parser;

  static const _userAgent = 'Lumen/1.0 (Flutter; EPG)';
  static const _headerTimeout = Duration(seconds: 30);
  static const _idleTimeout = Duration(seconds: 30);
  static const _totalTimeout = Duration(minutes: 3);

  final http.Client _http;
  final CatalogStore _store;
  final EpgXmltvParser _parser;

  Future<EpgSyncResult> sync({
    required String profileScope,
    required Uri uri,
    DateTime? now,
    Duration pastWindow = const Duration(hours: 6),
    Duration futureWindow = const Duration(hours: 48),
  }) async {
    if (uri.scheme != 'http' && uri.scheme != 'https') {
      throw const EpgSyncException('The guide URL must use HTTP or HTTPS.');
    }
    final sourceKey = epgSourceKey(uri);
    final previous = await _store.epgSourceState(profileScope, sourceKey);
    final request = http.Request('GET', uri)
      ..followRedirects = true
      ..maxRedirects = 3
      ..headers.addAll({
        'User-Agent': _userAgent,
        'Accept': 'application/xml, text/xml, application/gzip, */*',
        if (previous?.etag.isNotEmpty == true) 'If-None-Match': previous!.etag,
        if (previous?.lastModified.isNotEmpty == true)
          'If-Modified-Since': previous!.lastModified,
      });

    late http.StreamedResponse response;
    try {
      response = await _http.send(request).timeout(_headerTimeout);
    } on TimeoutException {
      throw const EpgSyncException(
        'The guide provider took too long to respond.',
      );
    } catch (_) {
      throw const EpgSyncException('Lumen could not reach the guide provider.');
    }

    final fetchedAt = (now ?? DateTime.now()).toUtc();
    if (response.statusCode == 304) {
      if (previous == null) {
        throw const EpgSyncException(
          'The guide provider returned no data for an empty cache.',
        );
      }
      await _store.markEpgNotModified(
        profileScope,
        sourceKey,
        fetchedAt: fetchedAt,
        etag: response.headers['etag'],
        lastModified: response.headers['last-modified'],
      );
      return EpgSyncResult(notModified: true, sourceKey: sourceKey);
    }
    if (response.statusCode != 200) {
      throw EpgSyncException(
        'The guide provider returned status ${response.statusCode}.',
      );
    }

    final contentLength = response.contentLength;
    if (contentLength != null && contentLength > _parser.maxDecompressedBytes) {
      throw const EpgSyncException('The guide exceeds Lumen’s safety limit.');
    }

    final generation = DateTime.now().microsecondsSinceEpoch;
    final windowStart = fetchedAt.subtract(pastWindow);
    final windowEnd = fetchedAt.add(futureWindow);
    await _store.beginEpgImport(profileScope, sourceKey, generation);
    try {
      final summary = await _parser
          .parse(
            response.stream.timeout(_idleTimeout),
            windowStartUtc: windowStart,
            windowEndUtc: windowEnd,
            onChannels: (batch) => _store.appendEpgChannels(
              profileScope,
              sourceKey,
              generation,
              batch,
            ),
            onProgrammes: (batch) => _store.appendEpgProgrammes(
              profileScope,
              sourceKey,
              generation,
              batch,
            ),
          )
          .timeout(_totalTimeout);
      await _store.completeEpgImport(
        profileScope,
        sourceKey,
        generation,
        etag: response.headers['etag'] ?? '',
        lastModified: response.headers['last-modified'] ?? '',
        fetchedAt: fetchedAt,
        validFrom: windowStart,
        validUntil: windowEnd,
      );
      return EpgSyncResult(
        notModified: false,
        sourceKey: sourceKey,
        summary: summary,
      );
    } catch (error) {
      await _store.abortEpgImport(
        profileScope,
        sourceKey,
        generation,
        sanitizedError: error is EpgParseException
            ? error.message
            : 'Guide ingestion failed.',
      );
      if (error is EpgParseException) {
        throw EpgSyncException(error.message);
      }
      if (error is TimeoutException) {
        throw const EpgSyncException(
          'The guide provider stopped responding during download.',
        );
      }
      rethrow;
    }
  }
}
