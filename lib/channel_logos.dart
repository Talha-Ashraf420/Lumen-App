import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

import 'epg.dart';
import 'models.dart';

const _catalogChannels = 'https://iptv-org.github.io/api/channels.json';
const _catalogLogos = 'https://iptv-org.github.io/api/logos.json';
const _userAgent = 'Lumen/1.0 (Flutter; channel artwork)';

/// Normalize provider decorations without making a fuzzy guess. IPTV lists
/// commonly add country prefixes and quality labels that are not part of the
/// broadcaster name.
String normalizeChannelName(String value) {
  var text = value.toLowerCase().trim();
  text = text.replaceAll('&', ' and ').replaceAll('+', ' plus ');
  text = text.replaceAll(
    RegExp(r'^[\s]*(?:us|usa|uk|gb|in|india|pk|ca|au)[\s]*[:|\-]+[\s]*'),
    '',
  );
  text = text.replaceAll(
    RegExp(
      r'[\(\[]\s*(?:4k|uhd|fhd|full\s*hd|hd|sd|hevc|h\.?26[45]|backup|raw)\s*[\)\]]',
    ),
    ' ',
  );
  text = text.replaceAll(
    RegExp(r'\b(?:4k|uhd|fhd|fullhd|hd|sd|hevc|backup)\b'),
    ' ',
  );
  return text.replaceAll(RegExp(r'[^a-z0-9]+'), '');
}

String _xmlText(String value) => value
    .replaceAll('&amp;', '&')
    .replaceAll('&quot;', '"')
    .replaceAll('&apos;', "'")
    .replaceAll('&#39;', "'")
    .replaceAll('&lt;', '<')
    .replaceAll('&gt;', '>');

bool _webUrl(String value) {
  final uri = Uri.tryParse(value.trim());
  return uri != null && (uri.scheme == 'http' || uri.scheme == 'https');
}

class XmltvLogoIndex {
  const XmltvLogoIndex(this.byId, this.byName);

  final Map<String, String> byId;
  final Map<String, String> byName;

  factory XmltvLogoIndex.fromEpgChannels(Iterable<EpgChannel> channels) {
    final byId = <String, String>{};
    final named = <String, List<String>>{};
    for (final channel in channels) {
      final logo = channel.icon.trim();
      if (logo.isEmpty || !_webUrl(logo)) continue;
      final id = channel.channelKey.trim().toLowerCase();
      if (id.isNotEmpty) byId.putIfAbsent(id, () => logo);
      for (final value in channel.displayNames) {
        final name = normalizeChannelName(value);
        if (name.isNotEmpty) named.putIfAbsent(name, () => []).add(logo);
      }
    }
    return XmltvLogoIndex(
      Map.unmodifiable(byId),
      Map.unmodifiable({
        for (final entry in named.entries)
          if (entry.value.toSet().length == 1) entry.key: entry.value.first,
      }),
    );
  }

  factory XmltvLogoIndex.parse(String xml) {
    final byId = <String, String>{};
    final named = <String, List<String>>{};
    final channelPattern = RegExp(
      r'<channel\b([^>]*)>(.*?)</channel\s*>',
      caseSensitive: false,
      dotAll: true,
    );
    final idPattern = RegExp(
      r'''\bid\s*=\s*["']([^"']+)["']''',
      caseSensitive: false,
    );
    final iconPattern = RegExp(
      r'''<icon\b[^>]*\bsrc\s*=\s*["']([^"']+)["']''',
      caseSensitive: false,
    );
    final namePattern = RegExp(
      r'<display-name\b[^>]*>(.*?)</display-name\s*>',
      caseSensitive: false,
      dotAll: true,
    );

    for (final match in channelPattern.allMatches(xml)) {
      final attributes = match.group(1) ?? '';
      final body = match.group(2) ?? '';
      final id = _xmlText(
        idPattern.firstMatch(attributes)?.group(1) ?? '',
      ).trim();
      final logo = _xmlText(
        iconPattern.firstMatch(body)?.group(1) ?? '',
      ).trim();
      if (logo.isEmpty || !_webUrl(logo)) continue;
      if (id.isNotEmpty) byId.putIfAbsent(id.toLowerCase(), () => logo);
      for (final nameMatch in namePattern.allMatches(body)) {
        final rawName = (nameMatch.group(1) ?? '').replaceAll(
          RegExp(r'<[^>]+>'),
          '',
        );
        final name = normalizeChannelName(_xmlText(rawName));
        if (name.isNotEmpty) named.putIfAbsent(name, () => []).add(logo);
      }
    }

    return XmltvLogoIndex(
      Map.unmodifiable(byId),
      Map.unmodifiable({
        for (final entry in named.entries)
          if (entry.value.toSet().length == 1) entry.key: entry.value.first,
      }),
    );
  }

  String? logoFor(LiveStream channel) {
    final id = channel.epgId.trim().toLowerCase();
    if (id.isNotEmpty && byId[id]?.isNotEmpty == true) return byId[id];
    for (final value in [channel.epgName, channel.name]) {
      final name = normalizeChannelName(value);
      if (name.isNotEmpty && byName[name]?.isNotEmpty == true) {
        return byName[name];
      }
    }
    return null;
  }
}

class _CatalogChannel {
  const _CatalogChannel({
    required this.id,
    required this.country,
    required this.logo,
  });

  final String id;
  final String country;
  final String logo;
}

/// A compact lookup built from IPTV-org's public channel and raster-logo
/// manifests. Matching is deliberately exact after normalization; ambiguous
/// names are rejected unless the playlist supplies a matching country.
class ChannelLogoCatalog {
  ChannelLogoCatalog._(this._byId, this._byName);

  final Map<String, _CatalogChannel> _byId;
  final Map<String, List<_CatalogChannel>> _byName;

  factory ChannelLogoCatalog.parse(String channelsJson, String logosJson) {
    final bestLogos = <String, ({String url, int score})>{};
    final logos = jsonDecode(logosJson);
    if (logos is List) {
      for (final raw in logos.whereType<Map>()) {
        if (raw['in_use'] == false) continue;
        final id = '${raw['channel'] ?? ''}'.trim().toLowerCase();
        final url = '${raw['url'] ?? ''}'.trim();
        final format = '${raw['format'] ?? ''}'.trim().toUpperCase();
        if (id.isEmpty || !_webUrl(url)) continue;
        if (!const {'PNG', 'JPEG', 'JPG', 'WEBP'}.contains(format)) continue;
        final width = raw['width'] is num ? (raw['width'] as num).toInt() : 0;
        final height = raw['height'] is num
            ? (raw['height'] as num).toInt()
            : 0;
        final size = width <= 0 || height <= 0
            ? 0
            : (width * height).clamp(0, 1000000);
        final formatScore = switch (format) {
          'PNG' => 3000000,
          'WEBP' => 2000000,
          _ => 1000000,
        };
        final score = formatScore + size;
        final current = bestLogos[id];
        if (current == null || score > current.score) {
          bestLogos[id] = (url: url, score: score);
        }
      }
    }

    final byId = <String, _CatalogChannel>{};
    final byName = <String, List<_CatalogChannel>>{};
    final channels = jsonDecode(channelsJson);
    if (channels is List) {
      for (final raw in channels.whereType<Map>()) {
        final id = '${raw['id'] ?? ''}'.trim();
        final logo = bestLogos[id.toLowerCase()]?.url ?? '';
        if (id.isEmpty || logo.isEmpty) continue;
        final item = _CatalogChannel(
          id: id,
          country: '${raw['country'] ?? ''}'.trim().toUpperCase(),
          logo: logo,
        );
        byId[id.toLowerCase()] = item;
        final names = <String>{'${raw['name'] ?? ''}'};
        final aliases = raw['alt_names'];
        if (aliases is List) names.addAll(aliases.map((value) => '$value'));
        for (final value in names) {
          final normalized = normalizeChannelName(value);
          if (normalized.isNotEmpty) {
            byName.putIfAbsent(normalized, () => []).add(item);
          }
        }
      }
    }
    return ChannelLogoCatalog._(
      Map.unmodifiable(byId),
      Map.unmodifiable(byName),
    );
  }

  String? logoFor(LiveStream channel) {
    final id = channel.epgId.trim().toLowerCase();
    if (id.isNotEmpty && _byId[id]?.logo.isNotEmpty == true) {
      return _byId[id]!.logo;
    }

    final country = _countryFor(channel);
    for (final rawName in [channel.epgName, channel.name]) {
      final name = normalizeChannelName(rawName);
      if (name.isEmpty) continue;
      final matches = _byName[name] ?? const <_CatalogChannel>[];
      if (matches.length == 1) return matches.first.logo;
      if (matches.isEmpty) continue;
      if (country.isNotEmpty) {
        final local = matches.where((item) => item.country == country).toList();
        if (local.length == 1) return local.first.logo;
      }
      final distinct = matches.map((item) => item.logo).toSet();
      if (distinct.length == 1) return distinct.first;
    }
    return null;
  }
}

String _countryFor(LiveStream channel) {
  final explicit = channel.countryCode.trim().toUpperCase();
  if (RegExp(r'^[A-Z]{2}$').hasMatch(explicit)) return explicit;
  final idCountry = RegExp(
    r'\.([a-z]{2})$',
    caseSensitive: false,
  ).firstMatch(channel.epgId)?.group(1);
  if (idCountry != null) return idCountry.toUpperCase();
  final hint = '${channel.categoryId} ${channel.name}'.toLowerCase();
  const countries = {
    'india': 'IN',
    'indian': 'IN',
    'pakistan': 'PK',
    'usa': 'US',
    'united states': 'US',
    'uk': 'GB',
    'united kingdom': 'GB',
    'canada': 'CA',
    'australia': 'AU',
  };
  for (final entry in countries.entries) {
    if (RegExp(
      '(^|[^a-z])${RegExp.escape(entry.key)}([^a-z]|\$)',
    ).hasMatch(hint)) {
      return entry.value;
    }
  }
  return '';
}

typedef LogoCatalogLoader = Future<ChannelLogoCatalog> Function();
typedef GuideLoader = Future<XmltvLogoIndex> Function(List<Uri> urls);

class ChannelLogoResolver {
  ChannelLogoResolver({
    required http.Client httpClient,
    LogoCatalogLoader? catalogLoader,
    GuideLoader? guideLoader,
  }) : _http = httpClient,
       _catalogLoaderOverride = catalogLoader,
       _guideLoaderOverride = guideLoader;

  final http.Client _http;
  final LogoCatalogLoader? _catalogLoaderOverride;
  final GuideLoader? _guideLoaderOverride;
  Future<ChannelLogoCatalog>? _catalog;
  final Map<String, Future<XmltvLogoIndex>> _guides = {};

  Future<List<LiveStream>> resolve(
    List<LiveStream> channels, {
    List<Uri> guideUrls = const [],
    XmltvLogoIndex? guideIndex,
  }) async {
    var enriched = List<LiveStream>.of(channels);
    if (guideIndex != null) {
      enriched = [
        for (final channel in enriched)
          _withResolved(channel, guideIndex.logoFor(channel), 'xmltv'),
      ];
    }
    if (guideUrls.isNotEmpty) {
      try {
        final guide = await _guideIndex(guideUrls);
        enriched = [
          for (final channel in enriched)
            _withResolved(channel, guide.logoFor(channel), 'xmltv'),
        ];
      } catch (_) {
        // A provider's optional guide must never block its channel list.
      }
    }

    if (!enriched.any((channel) => channel.effectiveIcon.isEmpty)) {
      return enriched;
    }
    try {
      final catalog = await _catalogIndex();
      return [
        for (final channel in enriched)
          channel.effectiveIcon.isNotEmpty
              ? channel
              : _withResolved(channel, catalog.logoFor(channel), 'iptv-org'),
      ];
    } catch (_) {
      return enriched;
    }
  }

  Future<ChannelLogoCatalog> _catalogIndex() async {
    final future = _catalog ??= _loadCatalog();
    try {
      return await future;
    } catch (_) {
      if (identical(_catalog, future)) _catalog = null;
      rethrow;
    }
  }

  LiveStream _withResolved(LiveStream channel, String? logo, String source) {
    if (logo == null || logo.isEmpty || !_webUrl(logo)) return channel;
    if (channel.icon.isEmpty) {
      return channel.copyWith(icon: logo, logoSource: source);
    }
    if (channel.fallbackIcon.isEmpty && channel.icon != logo) {
      return channel.copyWith(fallbackIcon: logo, logoSource: source);
    }
    return channel;
  }

  Future<XmltvLogoIndex> _guideIndex(List<Uri> urls) {
    final key = urls.map((uri) => uri.toString()).join('\n');
    return _guides.putIfAbsent(key, () async {
      final override = _guideLoaderOverride;
      if (override != null) return override(urls);
      final byId = <String, String>{};
      final byName = <String, String>{};
      for (final url in urls.take(3)) {
        try {
          final response = await _http
              .get(url, headers: const {'User-Agent': _userAgent})
              .timeout(const Duration(seconds: 35));
          if (response.statusCode != 200 ||
              response.bodyBytes.length > 50000000) {
            continue;
          }
          final xml = utf8.decode(response.bodyBytes, allowMalformed: true);
          final parsed = await Isolate.run(() => XmltvLogoIndex.parse(xml));
          byId.addAll(parsed.byId);
          byName.addAll(parsed.byName);
        } catch (_) {}
      }
      return XmltvLogoIndex(Map.unmodifiable(byId), Map.unmodifiable(byName));
    });
  }

  Future<ChannelLogoCatalog> _loadCatalog() async {
    final override = _catalogLoaderOverride;
    if (override != null) return override();
    final values = await Future.wait([
      _cachedPublicJson(Uri.parse(_catalogChannels), 'channels.json'),
      _cachedPublicJson(Uri.parse(_catalogLogos), 'logos.json'),
    ]);
    return Isolate.run(() => ChannelLogoCatalog.parse(values[0], values[1]));
  }

  Future<String> _cachedPublicJson(Uri uri, String filename) async {
    Directory support;
    try {
      support = await getApplicationSupportDirectory();
    } catch (_) {
      support = Directory('${Directory.systemTemp.path}/lumen_channel_logos');
    }
    final directory = Directory('${support.path}/channel_logos');
    await directory.create(recursive: true);
    final file = File('${directory.path}/$filename');
    if (await file.exists()) {
      final age = DateTime.now().difference(await file.lastModified());
      if (age < const Duration(days: 7)) return file.readAsString();
    }

    try {
      final response = await _http
          .get(uri, headers: const {'User-Agent': _userAgent})
          .timeout(const Duration(seconds: 40));
      if (response.statusCode != 200 || response.bodyBytes.length > 20000000) {
        throw const FormatException('Unexpected logo catalog response');
      }
      final value = utf8.decode(response.bodyBytes);
      jsonDecode(value); // Validate before replacing the last good manifest.
      final temporary = File('${file.path}.tmp');
      await temporary.writeAsString(value, flush: true);
      if (await file.exists()) await file.delete();
      await temporary.rename(file.path);
      return value;
    } catch (_) {
      if (await file.exists()) return file.readAsString();
      rethrow;
    }
  }
}
