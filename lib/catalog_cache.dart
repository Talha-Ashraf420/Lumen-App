import 'dart:async';
import 'dart:collection';

import 'package:flutter/foundation.dart' show ValueNotifier;

import 'catalog_store.dart';
import 'models.dart';
import 'xtream.dart';

/// Lifetime of a browse request. Cancelling skips queued work and discards
/// obsolete responses; it does not close the shared playback HTTP client.
class CatalogRequest {
  bool _cancelled = false;
  final Set<void Function()> _listeners = {};
  bool get isCancelled => _cancelled;

  void cancel() {
    if (_cancelled) return;
    _cancelled = true;
    for (final listener in _listeners.toList()) {
      listener();
    }
    _listeners.clear();
  }
}

class _CatalogCancelled implements Exception {}

/// Shared catalog cache used by Home, Search, browse pages and details.
///
/// Two details matter here:
///  * futures are cached immediately, so screens asking for the same content
///    while it is still loading share one request;
///  * provider work is gently scheduled, preventing a newly-built page from
///    opening a large burst of simultaneous connections.
class CatalogCache {
  CatalogCache._();
  static final CatalogCache instance = CatalogCache._();

  _RequestScheduler _requests = _RequestScheduler(maxConcurrent: 3);
  XtreamClient? _owner;
  int _epoch = 0;

  /// Screens listen to this for a quiet cached-first upgrade. The first read
  /// can paint SQLite data immediately; once the provider returns newer data,
  /// the relevant screen refreshes without showing a full-page loader.
  final ValueNotifier<int> revision = ValueNotifier<int>(0);

  Future<List<Category>>? _vodCategories;
  Future<List<Category>>? _seriesCategories;
  Future<List<Category>>? _liveCategories;

  final _vodStreams = _BoundedFutureCache<String, List<VodStream>>(
    maxEntries: 4,
    maxWeight: 2000,
    weight: (items) => items.length,
  );
  final _series = _BoundedFutureCache<String, List<Series>>(
    maxEntries: 4,
    maxWeight: 2000,
    weight: (items) => items.length,
  );
  final _liveStreams = _BoundedFutureCache<String, List<LiveStream>>(
    maxEntries: 4,
    maxWeight: 2000,
    weight: (items) => items.length,
  );
  final _vodInfo = _BoundedFutureCache<int, VodInfo>(maxEntries: 24);
  final _seriesInfo = _BoundedFutureCache<int, SeriesInfo>(maxEntries: 8);
  final Map<String, _BucketRefresh<dynamic>> _pageRefreshes = {};
  final Map<String, DateTime> _refreshedAt = {};
  final Map<String, Future<void>> _allImports = {};
  final Set<String> _logoEnrichments = {};

  int get debugRetainedCatalogItems =>
      _vodStreams.retainedWeight +
      _series.retainedWeight +
      _liveStreams.retainedWeight;
  int get debugPendingRequests => _requests.pending;
  int get debugActiveRequests => _requests.active;
  int get debugPageRefreshes => _pageRefreshes.length;

  bool _isCurrent(XtreamClient client, int epoch) =>
      epoch == _epoch && identical(_owner, client);

  Future<List<Category>> vod(XtreamClient client, {bool priority = false}) {
    _ensureOwner(client);
    if (client.creds.isDemo) {
      return _vodCategories ??= client.vodCategories();
    }
    return _vodCategories ??= _loadCategoriesCachedFirst(
      client,
      'movie',
      client.vodCategories,
      setMemory: (value) => _vodCategories = Future.value(value),
      priority: priority,
    );
  }

  Future<List<Category>> series(XtreamClient client, {bool priority = false}) {
    _ensureOwner(client);
    if (client.creds.isDemo) {
      return _seriesCategories ??= client.seriesCategories();
    }
    return _seriesCategories ??= _loadCategoriesCachedFirst(
      client,
      'series',
      client.seriesCategories,
      setMemory: (value) => _seriesCategories = Future.value(value),
      priority: priority,
    );
  }

  Future<List<Category>> live(XtreamClient client, {bool priority = false}) {
    _ensureOwner(client);
    if (client.creds.isDemo) {
      return _liveCategories ??= client.liveCategories();
    }
    return _liveCategories ??= _loadCategoriesCachedFirst(
      client,
      'live',
      client.liveCategories,
      setMemory: (value) => _liveCategories = Future.value(value),
      priority: priority,
    );
  }

  Future<List<VodStream>> vodStreams(
    XtreamClient client,
    String? categoryId, {
    bool priority = false,
  }) {
    _ensureOwner(client);
    final bucket = categoryId ?? '*';
    if (client.creds.isDemo) {
      return _memoized(
        _vodStreams,
        bucket,
        () => client.vodStreams(categoryId),
      );
    }
    return _memoized(
      _vodStreams,
      bucket,
      () => _loadItemsCachedFirst<VodStream>(
        client,
        () => client.vodStreams(categoryId),
        read: (scope) => CatalogStore.instance
            .vodPage(scope, bucket: bucket, limit: 100000)
            .then((page) => page.items),
        write: (scope, value, generation) => CatalogStore.instance.replaceVod(
          scope,
          bucket,
          value,
          generation: generation,
        ),
        setMemory: (value) => _vodStreams[bucket] = Future.value(value),
        priority: priority,
      ),
    );
  }

  Future<List<Series>> seriesItems(
    XtreamClient client,
    String? categoryId, {
    bool priority = false,
  }) {
    _ensureOwner(client);
    final bucket = categoryId ?? '*';
    if (client.creds.isDemo) {
      return _memoized(_series, bucket, () => client.series(categoryId));
    }
    return _memoized(
      _series,
      bucket,
      () => _loadItemsCachedFirst<Series>(
        client,
        () => client.series(categoryId),
        read: (scope) => CatalogStore.instance
            .seriesPage(scope, bucket: bucket, limit: 100000)
            .then((page) => page.items),
        write: (scope, value, generation) => CatalogStore.instance
            .replaceSeries(scope, bucket, value, generation: generation),
        setMemory: (value) => _series[bucket] = Future.value(value),
        priority: priority,
      ),
    );
  }

  Future<List<LiveStream>> liveStreams(
    XtreamClient client,
    String? categoryId, {
    bool priority = false,
  }) {
    _ensureOwner(client);
    final bucket = categoryId ?? '*';
    if (client.creds.isDemo) {
      return _memoized(
        _liveStreams,
        bucket,
        () => client.liveStreams(categoryId),
      );
    }
    return _memoized(
      _liveStreams,
      bucket,
      () => _loadItemsCachedFirst<LiveStream>(
        client,
        () => client.liveStreams(categoryId),
        read: (scope) => CatalogStore.instance
            .livePage(scope, bucket: bucket, limit: 100000)
            .then((page) => page.items),
        write: (scope, value, generation) => CatalogStore.instance.replaceLive(
          scope,
          bucket,
          value,
          generation: generation,
        ),
        setMemory: (value) {
          _liveStreams[bucket] = Future.value(value);
          _scheduleLogoEnrichment(client, bucket, value);
        },
        priority: priority,
      ),
    );
  }

  Future<VodInfo> vodInfo(XtreamClient client, int id) {
    _ensureOwner(client);
    return _memoized(
      _vodInfo,
      id,
      () => _requests.run(() => client.vodInfo(id), priority: true),
    );
  }

  Future<SeriesInfo> seriesInfo(XtreamClient client, int id) {
    _ensureOwner(client);
    return _memoized(
      _seriesInfo,
      id,
      () => _requests.run(() => client.seriesInfo(id), priority: true),
    );
  }

  void clear() {
    _owner = null;
    _reset();
  }

  void _ensureOwner(XtreamClient client) {
    if (_owner == null) {
      _owner = client;
      return;
    }
    if (identical(_owner, client)) return;
    _reset();
    _owner = client;
  }

  void _reset() {
    // Give the new account a fresh queue as well as fresh maps. Requests that
    // are already running may finish for their disposed screen, but cannot
    // delay or populate the new profile's cache.
    _requests.cancel();
    _requests = _RequestScheduler(maxConcurrent: 3);
    _epoch++;
    _vodCategories = null;
    _seriesCategories = null;
    _liveCategories = null;
    _vodStreams.clear();
    _series.clear();
    _liveStreams.clear();
    _vodInfo.clear();
    _seriesInfo.clear();
    _allImports.clear();
    _logoEnrichments.clear();
    _pageRefreshes.clear();
    _refreshedAt.clear();
  }

  void _scheduleLogoEnrichment(
    XtreamClient client,
    String bucket,
    List<LiveStream> channels, {
    bool Function()? isNeeded,
  }) {
    if (client.creds.isDemo || channels.isEmpty) return;
    final signature = Object.hash(
      bucket,
      Object.hashAll(
        channels.map(
          (channel) =>
              '${channel.streamId}|${channel.icon}|${channel.fallbackIcon}|'
              '${channel.epgId}|${channel.epgName}',
        ),
      ),
    ).toString();
    if (!_logoEnrichments.add(signature)) return;
    if (_logoEnrichments.length > 32) {
      _logoEnrichments.remove(_logoEnrichments.first);
    }
    final epoch = _epoch;
    final generation = _generation();
    final scope = client.catalogScope;
    final scheduler = _requests;
    bool needed() => _isCurrent(client, epoch) && (isNeeded?.call() ?? true);
    unawaited(() async {
      try {
        final enriched = await scheduler.run(
          () => client.enrichLiveLogos(channels),
          isNeeded: needed,
        );
        if (!needed()) {
          if (_isCurrent(client, epoch)) _logoEnrichments.remove(signature);
          return;
        }
        if (_sameItems(channels, enriched)) return;
        await CatalogStore.instance.replaceLive(
          scope,
          bucket,
          enriched,
          generation: generation,
        );
        if (epoch != _epoch || !identical(_owner, client)) return;
        _liveStreams[bucket] = Future.value(enriched);
        revision.value++;
      } catch (_) {
        // Artwork enrichment is optional and never affects channel playback.
        if (_isCurrent(client, epoch)) _logoEnrichments.remove(signature);
      }
    }());
  }

  Future<List<Category>> _loadCategoriesCachedFirst(
    XtreamClient client,
    String kind,
    Future<List<Category>> Function() fetch, {
    required void Function(List<Category>) setMemory,
    bool priority = false,
  }) async {
    final scope = client.catalogScope;
    final epoch = _epoch;
    final cached = await CatalogStore.instance.categories(scope, kind);
    if (!_isCurrent(client, epoch)) return cached;
    if (cached.isNotEmpty) {
      unawaited(
        _refreshCategories(
          client,
          scope,
          kind,
          fetch,
          cached,
          epoch: epoch,
          priority: priority,
          setMemory: setMemory,
        ),
      );
      return cached;
    }
    return _refreshCategories(
      client,
      scope,
      kind,
      fetch,
      cached,
      epoch: epoch,
      priority: priority,
      setMemory: setMemory,
      notify: false,
    );
  }

  Future<List<Category>> _refreshCategories(
    XtreamClient client,
    String scope,
    String kind,
    Future<List<Category>> Function() fetch,
    List<Category> previous, {
    required int epoch,
    required bool priority,
    required void Function(List<Category>) setMemory,
    bool notify = true,
  }) async {
    // Capture the generation before network work begins. If this account is
    // cleared while the request is in flight, CatalogStore's profile floor
    // rejects the late response.
    final generation = _generation();
    final scheduler = _requests;
    final fresh =
        (await _retry(
          () => scheduler.run(fetch, priority: priority),
          isCurrent: () => _isCurrent(client, epoch),
        )) ??
        const <Category>[];
    final reliable = fresh.isNotEmpty || previous.isEmpty ? fresh : previous;
    if (!_isCurrent(client, epoch)) return previous;
    if (fresh.isNotEmpty || client.creds.isM3u) {
      await CatalogStore.instance.replaceCategories(
        scope,
        kind,
        fresh,
        generation: generation,
      );
    }
    if (epoch == _epoch && identical(_owner, client)) {
      setMemory(reliable);
      if (notify && !_sameCategories(previous, reliable)) revision.value++;
    }
    return reliable;
  }

  Future<List<T>> _loadItemsCachedFirst<T>(
    XtreamClient client,
    Future<List<T>> Function() fetch, {
    required Future<List<T>> Function(String scope) read,
    required Future<bool> Function(String scope, List<T> value, int generation)
    write,
    required void Function(List<T>) setMemory,
    required bool priority,
  }) async {
    final scope = client.catalogScope;
    final epoch = _epoch;
    final scheduler = _requests;
    final cached = await read(scope);
    if (!_isCurrent(client, epoch)) return cached;
    Future<List<T>> refresh({bool notify = true}) async {
      // See _refreshCategories: request-start ordering prevents an obsolete
      // response from repopulating a profile after logout or account switch.
      final generation = _generation();
      List<T> fresh;
      try {
        fresh = await scheduler.run(fetch, priority: priority);
      } catch (_) {
        if (epoch == _epoch && identical(_owner, client)) setMemory(cached);
        return cached;
      }
      final reliable = fresh.isNotEmpty || cached.isEmpty ? fresh : cached;
      if (!_isCurrent(client, epoch)) return cached;
      if (fresh.isNotEmpty || client.creds.isM3u) {
        await write(scope, fresh, generation);
      }
      if (epoch == _epoch && identical(_owner, client)) {
        setMemory(reliable);
        if (notify && !_sameItems(cached, reliable)) revision.value++;
      }
      return reliable;
    }

    if (cached.isNotEmpty) {
      unawaited(refresh());
      return cached;
    }
    return refresh(notify: false);
  }

  /// Reads only the requested SQLite page. Refresh responses are indexed then
  /// released, rather than hydrating/retaining a second full cached category.
  Future<CatalogPage<T>> _indexedCategoryPage<T>(
    XtreamClient client,
    String kind,
    String bucket, {
    required Future<CatalogPage<T>> Function() read,
    required Future<List<T>> Function() fetch,
    required Future<bool> Function(List<T>, int) write,
    required CatalogPage<T> Function(List<T>) fallback,
    required Map<String, Future<List<T>>> memory,
    CatalogRequest? request,
  }) async {
    final epoch = _epoch;
    bool current() => _isCurrent(client, epoch) && request?.isCancelled != true;
    final cached = await read();
    if (!current()) return cached;
    final hasLocal =
        cached.items.isNotEmpty ||
        await CatalogStore.instance.hasItems(
          client.catalogScope,
          kind,
          bucket: bucket,
        );
    if (!current()) return cached;
    final retained = memory[bucket];
    if (!hasLocal && retained != null) return fallback(await retained);
    final key = '$kind:$bucket';
    final nextRefresh = _refreshedAt[key];
    if (hasLocal &&
        nextRefresh != null &&
        DateTime.now().isBefore(nextRefresh)) {
      return cached;
    }

    var job = _pageRefreshes[key] as _BucketRefresh<T>?;
    if (job == null || !job.needed) {
      final created = _BucketRefresh<T>();
      created.consumers.add(request);
      _pageRefreshes[key] = created;
      final scheduler = _requests;
      final generation = _generation();
      bool needed() => _isCurrent(client, epoch) && created.needed;
      created.future = () async {
        try {
          final fresh = await scheduler.run(
            fetch,
            priority: true,
            isNeeded: needed,
          );
          if (!needed()) return <T>[];
          final saved = (fresh.isNotEmpty || client.creds.isM3u)
              ? await write(fresh, generation)
              : false;
          if (!needed()) return <T>[];
          _recordRefresh(key, saved: saved);
          if (kind == 'live' && fresh is List<LiveStream>) {
            _scheduleLogoEnrichment(
              client,
              bucket,
              fresh.cast<LiveStream>(),
              isNeeded: needed,
            );
          }
          if (saved && hasLocal) revision.value++;
          return fresh;
        } catch (_) {
          // Cached content survives an outage or cancelled request.
          if (needed()) _recordRefresh(key, saved: false);
          return <T>[];
        } finally {
          if (identical(_pageRefreshes[key], created)) {
            _pageRefreshes.remove(key);
          }
        }
      }();
      job = created;
    } else {
      job.consumers.add(request);
    }
    final scheduler = _requests;
    void prune() => scheduler.prune();
    request?._listeners.add(prune);
    final refresh = job.future.whenComplete(
      () => request?._listeners.remove(prune),
    );
    if (hasLocal) {
      unawaited(refresh);
      return cached;
    }
    final fresh = await refresh;
    if (!current()) return cached;
    final stored = await read();
    if (fresh.isNotEmpty &&
        stored.items.isEmpty &&
        !await CatalogStore.instance.hasItems(
          client.catalogScope,
          kind,
          bucket: bucket,
        ) &&
        current()) {
      memory[bucket] = Future.value(fresh);
    }
    return stored.items.isNotEmpty || fresh.isEmpty ? stored : fallback(fresh);
  }

  void _recordRefresh(String key, {required bool saved}) {
    _refreshedAt.remove(key);
    _refreshedAt[key] = DateTime.now().add(
      saved ? const Duration(minutes: 5) : const Duration(seconds: 10),
    );
    if (_refreshedAt.length > 128) {
      _refreshedAt.remove(_refreshedAt.keys.first);
    }
  }

  Future<CatalogPage<VodStream>> vodPage(
    XtreamClient client, {
    String? categoryId,
    int offset = 0,
    int limit = CatalogStore.defaultPageSize,
    String query = '',
    String sort = 'default',
    CatalogRequest? request,
  }) async {
    _ensureOwner(client);
    final epoch = _epoch;
    if (client.creds.isDemo) {
      return _memoryPage(
        await vodStreams(client, categoryId),
        offset: offset,
        limit: limit,
        query: query,
        sort: sort,
        name: (item) => item.name,
        rating: (item) => item.rating,
        recent: (item) => mediaAddedValue(item.added),
        year: (item) => _yearValue(item.name),
      );
    }
    final bucket = categoryId ?? '*';
    final scope = client.catalogScope;
    if (categoryId != null) {
      return _indexedCategoryPage<VodStream>(
        client,
        'movie',
        bucket,
        memory: _vodStreams,
        request: request,
        read: () => CatalogStore.instance.vodPage(
          scope,
          bucket: bucket,
          offset: offset,
          limit: limit,
          query: query,
          sort: sort,
        ),
        fetch: () => client.vodStreams(categoryId),
        write: (items, generation) => CatalogStore.instance.replaceVod(
          scope,
          bucket,
          items,
          generation: generation,
        ),
        fallback: (items) => _memoryPage(
          items,
          offset: offset,
          limit: limit,
          query: query,
          sort: sort,
          name: (item) => item.name,
          rating: (item) => item.rating,
          recent: (item) => mediaAddedValue(item.added),
          year: (item) => _yearValue(item.name),
        ),
      );
    }
    final cached = await CatalogStore.instance.vodPage(
      scope,
      bucket: bucket,
      offset: offset,
      limit: limit,
      query: query,
      sort: sort,
    );
    final exactLocal = await CatalogStore.instance.hasItems(
      scope,
      'movie',
      bucket: bucket,
    );
    final anyLocal =
        exactLocal ||
        (categoryId == null &&
            await CatalogStore.instance.hasItems(scope, 'movie'));
    if (!_isCurrent(client, epoch) || request?.isCancelled == true) {
      return cached;
    }
    // Some Xtream panels time out or reject get_vod_streams without a
    // category even though their category endpoints are fast. Search those
    // buckets in provider order and stop at the first matching batch. This
    // makes a cold title search useful in seconds instead of waiting for the
    // unreliable whole-provider response and then importing every category.
    if (categoryId == null &&
        query.trim().isNotEmpty &&
        !exactLocal &&
        cached.items.isEmpty) {
      return _searchVodCategories(
        client,
        query: query,
        offset: offset,
        limit: limit,
        sort: sort,
        request: request,
      );
    }
    if (cached.items.isNotEmpty || anyLocal) {
      if (categoryId == null && !exactLocal) {
        unawaited(_importAllVod(client, scope));
      } else {
        unawaited(vodStreams(client, categoryId, priority: true));
      }
      return cached;
    }
    var direct = await vodStreams(client, categoryId, priority: true);
    if (!_isCurrent(client, epoch) || request?.isCancelled == true) {
      return cached;
    }
    if (categoryId == null && direct.isEmpty) {
      await _importAllVod(client, scope);
      if (!_isCurrent(client, epoch) || request?.isCancelled == true) {
        return cached;
      }
      direct = await vodStreams(client, categoryId, priority: true);
    }
    final stored = await CatalogStore.instance.vodPage(
      scope,
      bucket: bucket,
      offset: offset,
      limit: limit,
      query: query,
      sort: sort,
    );
    return stored.items.isNotEmpty || direct.isEmpty
        ? stored
        : _memoryPage(
            direct,
            offset: offset,
            limit: limit,
            query: query,
            sort: sort,
            name: (item) => item.name,
            rating: (item) => item.rating,
            recent: (item) => mediaAddedValue(item.added),
            year: (item) => _yearValue(item.name),
          );
  }

  Future<CatalogPage<VodStream>> _searchVodCategories(
    XtreamClient client, {
    required String query,
    required int offset,
    required int limit,
    required String sort,
    CatalogRequest? request,
  }) async {
    final epoch = _epoch;
    final categories = await vod(client, priority: true);
    final normalized = query.trim().toLowerCase();
    final matches = <int, VodStream>{};
    const batchSize = 6;
    for (var start = 0; start < categories.length; start += batchSize) {
      if (!_isCurrent(client, epoch) || request?.isCancelled == true) break;
      final batch = categories.skip(start).take(batchSize);
      final results = await Future.wait(
        batch.map(
          (category) => vodStreams(
            client,
            category.id,
            priority: true,
          ).catchError((_) => <VodStream>[]),
        ),
      );
      for (final items in results) {
        for (final item in items) {
          if (item.name.toLowerCase().contains(normalized)) {
            matches[item.streamId] = item;
          }
        }
      }
      if (matches.isNotEmpty) break;
    }
    return _memoryPage(
      matches.values.toList(growable: false),
      offset: offset,
      limit: limit,
      query: query,
      sort: sort,
      name: (item) => item.name,
      rating: (item) => item.rating,
      recent: (item) => mediaAddedValue(item.added),
      year: (item) => _yearValue(item.name),
    );
  }

  Future<CatalogPage<Series>> seriesPage(
    XtreamClient client, {
    String? categoryId,
    int offset = 0,
    int limit = CatalogStore.defaultPageSize,
    String query = '',
    String sort = 'default',
    CatalogRequest? request,
  }) async {
    _ensureOwner(client);
    final epoch = _epoch;
    if (client.creds.isDemo) {
      return _memoryPage(
        await seriesItems(client, categoryId),
        offset: offset,
        limit: limit,
        query: query,
        sort: sort,
        name: (item) => item.name,
        rating: (item) => item.rating,
        recent: (item) =>
            _yearValue(item.releaseDate.isEmpty ? item.name : item.releaseDate),
        year: (item) =>
            _yearValue(item.releaseDate.isEmpty ? item.name : item.releaseDate),
      );
    }
    final bucket = categoryId ?? '*';
    final scope = client.catalogScope;
    if (categoryId != null) {
      return _indexedCategoryPage<Series>(
        client,
        'series',
        bucket,
        memory: _series,
        request: request,
        read: () => CatalogStore.instance.seriesPage(
          scope,
          bucket: bucket,
          offset: offset,
          limit: limit,
          query: query,
          sort: sort,
        ),
        fetch: () => client.series(categoryId),
        write: (items, generation) => CatalogStore.instance.replaceSeries(
          scope,
          bucket,
          items,
          generation: generation,
        ),
        fallback: (items) => _memoryPage(
          items,
          offset: offset,
          limit: limit,
          query: query,
          sort: sort,
          name: (item) => item.name,
          rating: (item) => item.rating,
          recent: (item) => _yearValue(
            item.releaseDate.isEmpty ? item.name : item.releaseDate,
          ),
          year: (item) => _yearValue(
            item.releaseDate.isEmpty ? item.name : item.releaseDate,
          ),
        ),
      );
    }
    final cached = await CatalogStore.instance.seriesPage(
      scope,
      bucket: bucket,
      offset: offset,
      limit: limit,
      query: query,
      sort: sort,
    );
    final exactLocal = await CatalogStore.instance.hasItems(
      scope,
      'series',
      bucket: bucket,
    );
    final anyLocal =
        exactLocal ||
        (categoryId == null &&
            await CatalogStore.instance.hasItems(scope, 'series'));
    if (!_isCurrent(client, epoch) || request?.isCancelled == true) {
      return cached;
    }
    if (cached.items.isNotEmpty || anyLocal) {
      if (categoryId == null && !exactLocal) {
        unawaited(_importAllSeries(client, scope));
      } else {
        unawaited(seriesItems(client, categoryId, priority: true));
      }
      return cached;
    }
    var direct = await seriesItems(client, categoryId, priority: true);
    if (!_isCurrent(client, epoch) || request?.isCancelled == true) {
      return cached;
    }
    if (categoryId == null && direct.isEmpty) {
      await _importAllSeries(client, scope);
      if (!_isCurrent(client, epoch) || request?.isCancelled == true) {
        return cached;
      }
      direct = await seriesItems(client, categoryId, priority: true);
    }
    final stored = await CatalogStore.instance.seriesPage(
      scope,
      bucket: bucket,
      offset: offset,
      limit: limit,
      query: query,
      sort: sort,
    );
    return stored.items.isNotEmpty || direct.isEmpty
        ? stored
        : _memoryPage(
            direct,
            offset: offset,
            limit: limit,
            query: query,
            sort: sort,
            name: (item) => item.name,
            rating: (item) => item.rating,
            recent: (item) => _yearValue(
              item.releaseDate.isEmpty ? item.name : item.releaseDate,
            ),
            year: (item) => _yearValue(
              item.releaseDate.isEmpty ? item.name : item.releaseDate,
            ),
          );
  }

  Future<CatalogPage<LiveStream>> livePage(
    XtreamClient client, {
    String? categoryId,
    int offset = 0,
    int limit = CatalogStore.defaultPageSize,
    String query = '',
    String sort = 'default',
    CatalogRequest? request,
  }) async {
    _ensureOwner(client);
    final epoch = _epoch;
    if (client.creds.isDemo) {
      return _memoryPage(
        await liveStreams(client, categoryId),
        offset: offset,
        limit: limit,
        query: query,
        sort: sort,
        name: (item) => item.name,
        rating: (_) => 0,
        recent: (_) => 0,
        year: (_) => 0,
      );
    }
    final bucket = categoryId ?? '*';
    final scope = client.catalogScope;
    if (categoryId != null) {
      return _indexedCategoryPage<LiveStream>(
        client,
        'live',
        bucket,
        memory: _liveStreams,
        request: request,
        read: () => CatalogStore.instance.livePage(
          scope,
          bucket: bucket,
          offset: offset,
          limit: limit,
          query: query,
          sort: sort,
        ),
        fetch: () => client.liveStreams(categoryId),
        write: (items, generation) => CatalogStore.instance.replaceLive(
          scope,
          bucket,
          items,
          generation: generation,
        ),
        fallback: (items) => _memoryPage(
          items,
          offset: offset,
          limit: limit,
          query: query,
          sort: sort,
          name: (item) => item.name,
          rating: (_) => 0,
          recent: (_) => 0,
          year: (_) => 0,
        ),
      );
    }
    final cached = await CatalogStore.instance.livePage(
      scope,
      bucket: bucket,
      offset: offset,
      limit: limit,
      query: query,
      sort: sort,
    );
    final exactLocal = await CatalogStore.instance.hasItems(
      scope,
      'live',
      bucket: bucket,
    );
    final anyLocal =
        exactLocal ||
        (categoryId == null &&
            await CatalogStore.instance.hasItems(scope, 'live'));
    if (!_isCurrent(client, epoch) || request?.isCancelled == true) {
      return cached;
    }
    if (cached.items.isNotEmpty || anyLocal) {
      if (categoryId == null && !exactLocal) {
        unawaited(_importAllLive(client, scope));
      } else {
        unawaited(liveStreams(client, categoryId, priority: true));
      }
      return cached;
    }
    var direct = await liveStreams(client, categoryId, priority: true);
    if (!_isCurrent(client, epoch) || request?.isCancelled == true) {
      return cached;
    }
    if (categoryId == null && direct.isEmpty) {
      await _importAllLive(client, scope);
      if (!_isCurrent(client, epoch) || request?.isCancelled == true) {
        return cached;
      }
      direct = await liveStreams(client, categoryId, priority: true);
    }
    final stored = await CatalogStore.instance.livePage(
      scope,
      bucket: bucket,
      offset: offset,
      limit: limit,
      query: query,
      sort: sort,
    );
    return stored.items.isNotEmpty || direct.isEmpty
        ? stored
        : _memoryPage(
            direct,
            offset: offset,
            limit: limit,
            query: query,
            sort: sort,
            name: (item) => item.name,
            rating: (_) => 0,
            recent: (_) => 0,
            year: (_) => 0,
          );
  }

  CatalogPage<T> _memoryPage<T>(
    List<T> source, {
    required int offset,
    required int limit,
    required String query,
    required String sort,
    required String Function(T item) name,
    required double Function(T item) rating,
    required int Function(T item) recent,
    required int Function(T item) year,
  }) {
    final normalized = query.trim().toLowerCase();
    final values = source
        .where(
          (item) =>
              normalized.isEmpty ||
              name(item).toLowerCase().contains(normalized),
        )
        .toList();
    int byName(T a, T b) =>
        name(a).toLowerCase().compareTo(name(b).toLowerCase());
    switch (sort) {
      case 'az':
        values.sort(byName);
      case 'za':
        values.sort((a, b) => byName(b, a));
      case 'rating':
        values.sort((a, b) {
          final compared = rating(b).compareTo(rating(a));
          return compared == 0 ? byName(a, b) : compared;
        });
      case 'recent':
        values.sort((a, b) {
          final compared = recent(b).compareTo(recent(a));
          return compared == 0 ? byName(a, b) : compared;
        });
      case 'year':
        values.sort((a, b) {
          final compared = year(b).compareTo(year(a));
          return compared == 0 ? byName(a, b) : compared;
        });
    }
    if (offset >= values.length) {
      return CatalogPage<T>(
        items: const [],
        offset: offset,
        limit: limit,
        hasMore: false,
      );
    }
    final end = (offset + limit).clamp(0, values.length);
    return CatalogPage<T>(
      items: values.sublist(offset, end),
      offset: offset,
      limit: limit,
      hasMore: end < values.length,
    );
  }

  static int _yearValue(String value) =>
      int.tryParse(RegExp(r'(19|20)\d{2}').firstMatch(value)?.group(0) ?? '') ??
      0;

  Future<void> _importAllVod(XtreamClient client, String scope) =>
      _memoized(_allImports, 'movie', () async {
        final epoch = _epoch;
        final generation = _generation();
        final categories = await vod(client, priority: true);
        if (!_isCurrent(client, epoch)) return;
        final items = await _mergeCategories(
          categories,
          (id) => vodStreams(client, id),
          (item) => item.streamId,
          () => _isCurrent(client, epoch),
        );
        if (!_isCurrent(client, epoch) || items.isEmpty) return;
        await CatalogStore.instance.replaceVod(
          scope,
          '*',
          items,
          generation: generation,
        );
        if (_isCurrent(client, epoch)) {
          _vodStreams['*'] = Future.value(items);
          revision.value++;
        }
      });

  Future<void> _importAllSeries(XtreamClient client, String scope) =>
      _memoized(_allImports, 'series', () async {
        final epoch = _epoch;
        final generation = _generation();
        final categories = await series(client, priority: true);
        if (!_isCurrent(client, epoch)) return;
        final items = await _mergeCategories(
          categories,
          (id) => seriesItems(client, id),
          (item) => item.seriesId,
          () => _isCurrent(client, epoch),
        );
        if (!_isCurrent(client, epoch) || items.isEmpty) return;
        await CatalogStore.instance.replaceSeries(
          scope,
          '*',
          items,
          generation: generation,
        );
        if (_isCurrent(client, epoch)) {
          _series['*'] = Future.value(items);
          revision.value++;
        }
      });

  Future<void> _importAllLive(XtreamClient client, String scope) =>
      _memoized(_allImports, 'live', () async {
        final epoch = _epoch;
        final generation = _generation();
        final categories = await live(client, priority: true);
        if (!_isCurrent(client, epoch)) return;
        final items = await _mergeCategories(
          categories,
          (id) => liveStreams(client, id),
          (item) => item.streamId,
          () => _isCurrent(client, epoch),
        );
        if (!_isCurrent(client, epoch) || items.isEmpty) return;
        await CatalogStore.instance.replaceLive(
          scope,
          '*',
          items,
          generation: generation,
        );
        if (_isCurrent(client, epoch)) {
          _liveStreams['*'] = Future.value(items);
          revision.value++;
        }
      });

  Future<List<T>> _mergeCategories<T, K>(
    List<Category> categories,
    Future<List<T>> Function(String categoryId) fetch,
    K Function(T item) identity,
    bool Function() isCurrent,
  ) async {
    final unique = <K, T>{};
    const batchSize = 4;
    for (var i = 0; i < categories.length; i += batchSize) {
      if (!isCurrent()) return const [];
      final batch = categories.skip(i).take(batchSize);
      final results = await Future.wait(
        batch.map((category) => fetch(category.id).catchError((_) => <T>[])),
      );
      if (!isCurrent()) return const [];
      for (final items in results) {
        for (final item in items) {
          unique[identity(item)] = item;
        }
      }
    }
    return unique.values.toList(growable: false);
  }

  static int _generation() => DateTime.now().microsecondsSinceEpoch;

  static bool _sameCategories(List<Category> a, List<Category> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i].id != b[i].id || a[i].name != b[i].name) return false;
    }
    return true;
  }

  static bool _sameItems<T>(List<T> a, List<T> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (_itemSignature(a[i]) != _itemSignature(b[i])) return false;
    }
    return true;
  }

  static String _itemSignature(Object? item) => switch (item) {
    VodStream value =>
      '${value.streamId}|${value.name}|${value.icon}|'
          '${value.categoryId}|${value.containerExtension}|${value.rating}|'
          '${value.sourceScope}|${value.sourceLabel}',
    Series value =>
      '${value.seriesId}|${value.name}|${value.cover}|'
          '${value.categoryId}|${value.rating}|${value.releaseDate}|'
          '${value.sourceScope}|${value.sourceLabel}',
    LiveStream value =>
      '${value.streamId}|${value.name}|${value.icon}|'
          '${value.categoryId}|${value.epgId}|${value.epgName}|'
          '${value.countryCode}|${value.fallbackIcon}|${value.logoSource}|'
          '${value.sourceScope}|${value.sourceLabel}',
    _ => '$item',
  };

  /// Returns the first non-empty result across a few attempts. Empty category
  /// lists are allowed after retrying (plain M3U profiles legitimately have no
  /// movie or series catalog).
  static Future<List<Category>?> _retry(
    Future<List<Category>> Function() fetch, {
    required bool Function() isCurrent,
  }) async {
    for (var attempt = 0; attempt < 3; attempt++) {
      if (!isCurrent()) return null;
      try {
        final result = await fetch();
        if (result.isNotEmpty) return result;
      } catch (_) {}
      if (!isCurrent()) return null;
      if (attempt < 2) {
        await Future<void>.delayed(Duration(milliseconds: 350 * (attempt + 1)));
      }
    }
    return null;
  }

  static Future<T> _memoized<K, T>(
    Map<K, Future<T>> cache,
    K key,
    Future<T> Function() load,
  ) {
    final existing = cache[key];
    if (existing != null) return existing;
    final future = load();
    cache[key] = future;
    future.then<void>(
      (_) {},
      onError: (Object _, StackTrace _) {
        if (identical(cache[key], future)) cache.remove(key);
      },
    );
    return future;
  }
}

class _RequestScheduler {
  _RequestScheduler({required this.maxConcurrent});

  final int maxConcurrent;
  int _active = 0;
  bool _cancelled = false;
  int get active => _active;
  int get pending => _priority.length + _normal.length;
  final List<_ScheduledRequest<dynamic>> _priority = [];
  final List<_ScheduledRequest<dynamic>> _normal = [];

  Future<T> run<T>(
    Future<T> Function() task, {
    bool priority = false,
    bool Function()? isNeeded,
  }) {
    final completer = Completer<T>();
    final request = _ScheduledRequest<T>(task, completer, isNeeded);
    if (_cancelled || !(isNeeded?.call() ?? true)) {
      request.cancel();
      return completer.future;
    }
    (priority ? _priority : _normal).add(request);
    _drain();
    return completer.future;
  }

  void cancel() {
    _cancelled = true;
    prune();
  }

  void prune() {
    for (final queue in [_priority, _normal]) {
      queue.removeWhere((request) {
        if (!_cancelled && request.needed) return false;
        request.cancel();
        return true;
      });
    }
  }

  void _drain() {
    prune();
    while (_active < maxConcurrent &&
        (_priority.isNotEmpty || _normal.isNotEmpty)) {
      final request = _priority.isNotEmpty
          ? _priority.removeAt(0)
          : _normal.removeAt(0);
      _active++;
      request.run().whenComplete(() {
        _active--;
        _drain();
      });
    }
  }
}

class _ScheduledRequest<T> {
  _ScheduledRequest(this.task, this.completer, this.isNeeded);

  final Future<T> Function() task;
  final Completer<T> completer;
  final bool Function()? isNeeded;
  bool get needed => isNeeded?.call() ?? true;

  void cancel() => completer.completeError(_CatalogCancelled());

  Future<void> run() async {
    try {
      completer.complete(await task());
    } catch (error, stackTrace) {
      completer.completeError(error, stackTrace);
    }
  }
}

class _BucketRefresh<T> {
  final Set<CatalogRequest?> consumers = {};
  late Future<List<T>> future;
  bool get needed => consumers.any((request) => request?.isCancelled != true);
}

/// In-flight futures remain shared. Only settled entries are evicted, so a
/// large response can be returned without retaining it for the whole session.
class _BoundedFutureCache<K, T> extends MapBase<K, Future<T>> {
  _BoundedFutureCache({
    required this.maxEntries,
    this.maxWeight,
    int Function(T)? weight,
  }) : _weight = weight ?? ((_) => 1);

  final int maxEntries;
  final int? maxWeight;
  final int Function(T) _weight;
  final _values = <K, Future<T>>{};
  final Map<K, int> _weights = {};
  int get retainedWeight => _weights.values.fold(0, (a, b) => a + b);

  @override
  Future<T>? operator [](Object? key) {
    final value = _values.remove(key);
    if (value != null) _values[key as K] = value;
    return value;
  }

  @override
  void operator []=(K key, Future<T> value) {
    remove(key);
    _values[key] = value;
    value.then<void>(
      (result) {
        if (!identical(_values[key], value)) return;
        _weights[key] = _weight(result);
        if (maxWeight != null && _weights[key]! > maxWeight!) {
          remove(key);
          return;
        }
        while (_weights.length > maxEntries ||
            (maxWeight != null && retainedWeight > maxWeight!)) {
          final oldest = _values.keys.firstWhere(_weights.containsKey);
          remove(oldest);
        }
      },
      onError: (Object _, StackTrace _) {
        if (identical(_values[key], value)) remove(key);
      },
    );
  }

  @override
  Iterable<K> get keys => _values.keys;
  @override
  Future<T>? remove(Object? key) {
    _weights.remove(key);
    return _values.remove(key);
  }

  @override
  void clear() {
    _weights.clear();
    _values.clear();
  }
}
