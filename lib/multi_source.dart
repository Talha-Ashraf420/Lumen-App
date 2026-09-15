import 'catalog_store.dart';
import 'epg.dart';
import 'epg_loader.dart';
import 'models.dart';
import 'store.dart';
import 'xtream.dart';

/// A source-aware facade over multiple IPTV services.
///
/// Every provider keeps its own transport and refresh request. Provider IDs are
/// namespaced before they reach the UI/cache so identical Xtream IDs cannot
/// collide, and detail/playback calls are routed back to the owning service.
class MultiSourceXtreamClient extends XtreamClient {
  MultiSourceXtreamClient(
    super.creds,
    List<XtreamCredentials> profiles, {
    XtreamClient Function(XtreamCredentials)? clientFactory,
  }) : _entries = _buildEntries(creds, profiles, clientFactory) {
    for (final entry in _entries) {
      _entryByCode[entry.code] = entry;
      _entryByScope[entry.scope] = entry;
    }
    catalogScope = Store.combinedCatalogScope(
      _entries.map((entry) => entry.credentials),
    );
  }

  final List<_SourceEntry> _entries;
  final Map<int, _SourceEntry> _entryByCode = {};
  final Map<String, _SourceEntry> _entryByScope = {};
  final Map<String, _SourceEntry> _guideOwners = {};

  @override
  late final String catalogScope;

  bool get combinesSources => _entries.length > 1;
  int get sourceCount => _entries.length;

  @override
  bool get supportsMovieCatalog =>
      _entries.any((source) => !source.credentials.isM3u);

  @override
  bool get supportsSeriesCatalog =>
      _entries.any((source) => !source.credentials.isM3u);

  @override
  bool supportsShortEpg(int streamId) {
    final decoded = _decodeId(streamId);
    return !decoded.source.credentials.isDemo &&
        !decoded.source.credentials.isM3u;
  }

  static List<_SourceEntry> _buildEntries(
    XtreamCredentials primary,
    List<XtreamCredentials> profiles,
    XtreamClient Function(XtreamCredentials)? clientFactory,
  ) {
    final factory = clientFactory ?? XtreamClient.new;
    final unique = <XtreamCredentials>[primary];
    for (final profile in profiles) {
      if (!unique.any((value) => Store.sameProfile(value, profile))) {
        unique.add(profile);
      }
    }
    final usedCodes = <int>{};
    return unique
        .map((profile) {
          final scope = Store.profileScope(profile);
          var code = int.parse(scope.substring(0, 5), radix: 16);
          while (!usedCodes.add(code)) {
            code = (code + 1) & 0xfffff;
          }
          final host = profile.isM3u
              ? Uri.tryParse(profile.m3uUrl ?? '')?.host ?? 'Playlist'
              : Uri.tryParse(profile.baseUrl)?.host ?? profile.baseUrl;
          final label = host.isEmpty ? 'IPTV service' : host;
          return _SourceEntry(
            credentials: profile,
            client: factory(profile),
            scope: scope,
            code: code,
            label: label,
          );
        })
        .toList(growable: false);
  }

  static const _idMask = 0x7fffffff;

  int _encodeId(_SourceEntry source, int original) =>
      source.code * 0x80000000 + (original & _idMask);

  ({_SourceEntry source, int original}) _decodeId(int value) {
    final source = _entryByCode[value ~/ 0x80000000] ?? _entries.first;
    return (source: source, original: value & _idMask);
  }

  String _encodeCategory(_SourceEntry source, String original) =>
      '${source.scope}::$original';

  ({_SourceEntry source, String original}) _decodeCategory(String value) {
    final separator = value.indexOf('::');
    if (separator > 0) {
      final source = _entryByScope[value.substring(0, separator)];
      if (source != null) {
        return (source: source, original: value.substring(separator + 2));
      }
    }
    return (source: _entries.first, original: value);
  }

  Future<List<T>> _merge<T>(
    Future<List<T>> Function(_SourceEntry source) load,
  ) async {
    final batches = await Future.wait(
      _entries.map((source) async {
        try {
          return await load(source);
        } catch (_) {
          // A slow or unavailable provider must not take the other services'
          // library down with it. CatalogCache retains the last good combined
          // snapshot while this facade publishes every successful source.
          return <T>[];
        }
      }),
    );
    return [for (final batch in batches) ...batch];
  }

  int _generation() => DateTime.now().microsecondsSinceEpoch;

  Future<List<Category>> _sourceCategories(
    _SourceEntry source,
    String kind,
    Future<List<Category>> Function() fetch,
  ) async {
    try {
      final fresh = await fetch();
      await CatalogStore.instance.replaceCategories(
        source.scope,
        kind,
        fresh,
        generation: _generation(),
      );
      return fresh;
    } catch (_) {
      final cached = await CatalogStore.instance.categories(source.scope, kind);
      // Builds before the dedicated combined cache scope could write tagged
      // category rows over the primary provider's raw cache. Ignore those
      // legacy rows while offline; a successful provider refresh replaces
      // them atomically with clean records.
      return cached
          .where((value) => !_isNamespacedCategory(value.id))
          .toList(growable: false);
    }
  }

  bool _isNamespacedCategory(String id) {
    final separator = id.indexOf('::');
    return separator > 0 &&
        _entryByScope.containsKey(id.substring(0, separator));
  }

  Future<List<LiveStream>> _sourceLive(
    _SourceEntry source,
    String? categoryId,
  ) async {
    final bucket = categoryId ?? '*';
    try {
      final fresh = await source.client.liveStreams(categoryId);
      await CatalogStore.instance.replaceLive(
        source.scope,
        bucket,
        fresh,
        generation: _generation(),
      );
      return fresh;
    } catch (_) {
      final cached = (await CatalogStore.instance.livePage(
        source.scope,
        bucket: bucket,
        limit: 1000000,
      )).items;
      return cached
          .where(
            (value) =>
                value.sourceScope.isEmpty &&
                !_isNamespacedCategory(value.categoryId),
          )
          .toList(growable: false);
    }
  }

  Future<List<VodStream>> _sourceVod(
    _SourceEntry source,
    String? categoryId,
  ) async {
    final bucket = categoryId ?? '*';
    try {
      final fresh = await source.client.vodStreams(categoryId);
      await CatalogStore.instance.replaceVod(
        source.scope,
        bucket,
        fresh,
        generation: _generation(),
      );
      return fresh;
    } catch (_) {
      final cached = (await CatalogStore.instance.vodPage(
        source.scope,
        bucket: bucket,
        limit: 1000000,
      )).items;
      return cached
          .where(
            (value) =>
                value.sourceScope.isEmpty &&
                !_isNamespacedCategory(value.categoryId),
          )
          .toList(growable: false);
    }
  }

  Future<List<Series>> _sourceSeries(
    _SourceEntry source,
    String? categoryId,
  ) async {
    final bucket = categoryId ?? '*';
    try {
      final fresh = await source.client.series(categoryId);
      await CatalogStore.instance.replaceSeries(
        source.scope,
        bucket,
        fresh,
        generation: _generation(),
      );
      return fresh;
    } catch (_) {
      final cached = (await CatalogStore.instance.seriesPage(
        source.scope,
        bucket: bucket,
        limit: 1000000,
      )).items;
      return cached
          .where(
            (value) =>
                value.sourceScope.isEmpty &&
                !_isNamespacedCategory(value.categoryId),
          )
          .toList(growable: false);
    }
  }

  List<Category> _tagCategories(_SourceEntry source, List<Category> values) =>
      values
          .map(
            (value) => Category(
              _encodeCategory(source, value.id),
              '${value.name} · ${source.label}',
              sourceScope: source.scope,
              sourceLabel: source.label,
            ),
          )
          .toList(growable: false);

  List<LiveStream> _tagLive(_SourceEntry source, List<LiveStream> values) =>
      values
          .map(
            (value) => LiveStream(
              _encodeId(source, value.streamId),
              value.name,
              value.icon,
              _encodeCategory(source, value.categoryId),
              epgId: value.epgId,
              epgName: value.epgName,
              countryCode: value.countryCode,
              fallbackIcon: value.fallbackIcon,
              logoSource: value.logoSource,
              sourceScope: source.scope,
              sourceLabel: source.label,
            ),
          )
          .toList(growable: false);

  List<VodStream> _tagVod(_SourceEntry source, List<VodStream> values) => values
      .map(
        (value) => VodStream(
          _encodeId(source, value.streamId),
          value.name,
          value.icon,
          _encodeCategory(source, value.categoryId),
          value.containerExtension,
          value.rating,
          value.added,
          sourceScope: source.scope,
          sourceLabel: source.label,
        ),
      )
      .toList(growable: false);

  List<Series> _tagSeries(_SourceEntry source, List<Series> values) => values
      .map(
        (value) => Series(
          _encodeId(source, value.seriesId),
          value.name,
          value.cover,
          value.plot,
          value.genre,
          value.rating,
          value.releaseDate,
          _encodeCategory(source, value.categoryId),
          sourceScope: source.scope,
          sourceLabel: source.label,
        ),
      )
      .toList(growable: false);

  @override
  Future<Map<String, dynamic>> authenticate() =>
      _entries.first.client.authenticate();

  @override
  Future<List<Category>> liveCategories() => _merge(
    (source) async => _tagCategories(
      source,
      await _sourceCategories(source, 'live', source.client.liveCategories),
    ),
  );

  @override
  Future<List<Category>> vodCategories() => _merge(
    (source) async => _tagCategories(
      source,
      await _sourceCategories(source, 'movie', source.client.vodCategories),
    ),
  );

  @override
  Future<List<Category>> seriesCategories() => _merge(
    (source) async => _tagCategories(
      source,
      await _sourceCategories(source, 'series', source.client.seriesCategories),
    ),
  );

  @override
  Future<List<LiveStream>> liveStreams(String? categoryId) async {
    if (categoryId != null) {
      final decoded = _decodeCategory(categoryId);
      return _tagLive(
        decoded.source,
        await _sourceLive(decoded.source, decoded.original),
      );
    }
    return _merge(
      (source) async => _tagLive(source, await _sourceLive(source, null)),
    );
  }

  @override
  Future<List<VodStream>> vodStreams(String? categoryId) async {
    if (categoryId != null) {
      final decoded = _decodeCategory(categoryId);
      return _tagVod(
        decoded.source,
        await _sourceVod(decoded.source, decoded.original),
      );
    }
    return _merge(
      (source) async => _tagVod(source, await _sourceVod(source, null)),
    );
  }

  @override
  Future<List<Series>> series(String? categoryId) async {
    if (categoryId != null) {
      final decoded = _decodeCategory(categoryId);
      return _tagSeries(
        decoded.source,
        await _sourceSeries(decoded.source, decoded.original),
      );
    }
    return _merge(
      (source) async => _tagSeries(source, await _sourceSeries(source, null)),
    );
  }

  @override
  Future<VodInfo> vodInfo(int id) {
    final decoded = _decodeId(id);
    return decoded.source.client.vodInfo(decoded.original);
  }

  @override
  Future<SeriesInfo> seriesInfo(int id) async {
    final decoded = _decodeId(id);
    final info = await decoded.source.client.seriesInfo(decoded.original);
    return SeriesInfo(
      cover: info.cover,
      backdrop: info.backdrop,
      plot: info.plot,
      genre: info.genre,
      rating: info.rating,
      releaseDate: info.releaseDate,
      episodes: info.episodes.map(
        (season, episodes) => MapEntry(
          season,
          episodes
              .map(
                (episode) => Episode(
                  '${decoded.source.scope}::${episode.id}',
                  episode.episodeNum,
                  episode.title,
                  episode.containerExtension,
                  episode.season,
                  episode.image,
                ),
              )
              .toList(growable: false),
        ),
      ),
    );
  }

  ({_SourceEntry source, Object original}) _decodeObjectId(Object id) {
    if (id is int) {
      final decoded = _decodeId(id);
      return (source: decoded.source, original: decoded.original);
    }
    final text = '$id';
    final separator = text.indexOf('::');
    if (separator > 0) {
      final source = _entryByScope[text.substring(0, separator)];
      if (source != null) {
        return (source: source, original: text.substring(separator + 2));
      }
    }
    return (source: _entries.first, original: id);
  }

  @override
  Map<String, String> streamHeaders(Object id) {
    final decoded = _decodeObjectId(id);
    return decoded.source.client.streamHeaders(decoded.original);
  }

  @override
  String streamUrl(String kind, Object id, {String ext = 'ts'}) {
    final decoded = _decodeObjectId(id);
    return decoded.source.client.streamUrl(kind, decoded.original, ext: ext);
  }

  @override
  Future<List<EpgProgramme>> shortEpg(int streamId, {int limit = 4}) {
    final decoded = _decodeId(streamId);
    return decoded.source.client.shortEpg(decoded.original, limit: limit);
  }

  @override
  Future<List<Uri>> epgGuideUrls() async {
    _guideOwners.clear();
    final urls = <Uri>[];
    for (final source in _entries) {
      try {
        for (final url in await source.client.epgGuideUrls()) {
          _guideOwners[url.toString()] = source;
          urls.add(url);
        }
      } catch (_) {}
    }
    return urls;
  }

  @override
  Future<EpgSyncResult> syncEpgGuide(
    Uri uri, {
    CatalogStore? store,
    DateTime? now,
    String? profileScope,
  }) async {
    if (_guideOwners.isEmpty) await epgGuideUrls();
    final source = _guideOwners[uri.toString()] ?? _entries.first;
    return source.client.syncEpgGuide(
      uri,
      store: store,
      now: now,
      profileScope: profileScope,
    );
  }

  @override
  void close() {
    for (final entry in _entries) {
      entry.client.close();
    }
    super.close();
  }
}

class _SourceEntry {
  const _SourceEntry({
    required this.credentials,
    required this.client,
    required this.scope,
    required this.code,
    required this.label,
  });

  final XtreamCredentials credentials;
  final XtreamClient client;
  final String scope;
  final int code;
  final String label;
}
