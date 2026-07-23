import 'dart:async';

import 'package:flutter/foundation.dart' show ValueNotifier;

import 'catalog_store.dart';
import 'models.dart';
import 'store.dart';
import 'xtream.dart';

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

  final Map<String, Future<List<VodStream>>> _vodStreams = {};
  final Map<String, Future<List<Series>>> _series = {};
  final Map<String, Future<List<LiveStream>>> _liveStreams = {};
  final Map<int, Future<VodInfo>> _vodInfo = {};
  final Map<int, Future<SeriesInfo>> _seriesInfo = {};
  final Map<String, Future<void>> _allImports = {};

  Future<List<Category>> vod(XtreamClient client, {bool priority = false}) {
    _ensureOwner(client);
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
        setMemory: (value) => _liveStreams[bucket] = Future.value(value),
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
  }

  Future<List<Category>> _loadCategoriesCachedFirst(
    XtreamClient client,
    String kind,
    Future<List<Category>> Function() fetch, {
    required void Function(List<Category>) setMemory,
    bool priority = false,
  }) async {
    final scope = Store.profileScope(client.creds);
    final epoch = _epoch;
    final cached = await CatalogStore.instance.categories(scope, kind);
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
    final fresh =
        (await _retry(() => _requests.run(fetch, priority: priority))) ??
        const <Category>[];
    final reliable = fresh.isNotEmpty || previous.isEmpty ? fresh : previous;
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
    final scope = Store.profileScope(client.creds);
    final epoch = _epoch;
    final cached = await read(scope);
    Future<List<T>> refresh({bool notify = true}) async {
      // See _refreshCategories: request-start ordering prevents an obsolete
      // response from repopulating a profile after logout or account switch.
      final generation = _generation();
      List<T> fresh;
      try {
        fresh = await _requests.run(fetch, priority: priority);
      } catch (_) {
        return cached;
      }
      final reliable = fresh.isNotEmpty || cached.isEmpty ? fresh : cached;
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

  /// Page APIs used by catalog/search surfaces that do not need an entire
  /// provider response in memory. Network refresh still flows through the
  /// ordinary methods above and atomically replaces the indexed bucket.
  Future<CatalogPage<VodStream>> vodPage(
    XtreamClient client, {
    String? categoryId,
    int offset = 0,
    int limit = CatalogStore.defaultPageSize,
    String query = '',
    String sort = 'default',
  }) async {
    _ensureOwner(client);
    final bucket = categoryId ?? '*';
    final scope = Store.profileScope(client.creds);
    final cached = await CatalogStore.instance.vodPage(
      scope,
      bucket: bucket,
      offset: offset,
      limit: limit,
      query: query,
      sort: sort,
    );
    if (cached.items.isNotEmpty) {
      unawaited(vodStreams(client, categoryId, priority: true));
      return cached;
    }
    var direct = await vodStreams(client, categoryId, priority: true);
    if (categoryId == null && direct.isEmpty) {
      await _importAllVod(client, scope);
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
            recent: (item) => int.tryParse(item.added) ?? 0,
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
  }) async {
    _ensureOwner(client);
    final bucket = categoryId ?? '*';
    final scope = Store.profileScope(client.creds);
    final cached = await CatalogStore.instance.seriesPage(
      scope,
      bucket: bucket,
      offset: offset,
      limit: limit,
      query: query,
      sort: sort,
    );
    if (cached.items.isNotEmpty) {
      unawaited(seriesItems(client, categoryId, priority: true));
      return cached;
    }
    var direct = await seriesItems(client, categoryId, priority: true);
    if (categoryId == null && direct.isEmpty) {
      await _importAllSeries(client, scope);
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
  }) async {
    _ensureOwner(client);
    final bucket = categoryId ?? '*';
    final scope = Store.profileScope(client.creds);
    final cached = await CatalogStore.instance.livePage(
      scope,
      bucket: bucket,
      offset: offset,
      limit: limit,
      query: query,
      sort: sort,
    );
    if (cached.items.isNotEmpty) {
      unawaited(liveStreams(client, categoryId, priority: true));
      return cached;
    }
    var direct = await liveStreams(client, categoryId, priority: true);
    if (categoryId == null && direct.isEmpty) {
      await _importAllLive(client, scope);
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
        final generation = _generation();
        final categories = await vod(client, priority: true);
        final items = await _mergeCategories(
          categories,
          (id) => vodStreams(client, id),
          (item) => item.streamId,
        );
        if (items.isEmpty) return;
        await CatalogStore.instance.replaceVod(
          scope,
          '*',
          items,
          generation: generation,
        );
        if (identical(_owner, client)) {
          _vodStreams['*'] = Future.value(items);
        }
      });

  Future<void> _importAllSeries(XtreamClient client, String scope) =>
      _memoized(_allImports, 'series', () async {
        final generation = _generation();
        final categories = await series(client, priority: true);
        final items = await _mergeCategories(
          categories,
          (id) => seriesItems(client, id),
          (item) => item.seriesId,
        );
        if (items.isEmpty) return;
        await CatalogStore.instance.replaceSeries(
          scope,
          '*',
          items,
          generation: generation,
        );
        if (identical(_owner, client)) {
          _series['*'] = Future.value(items);
        }
      });

  Future<void> _importAllLive(XtreamClient client, String scope) =>
      _memoized(_allImports, 'live', () async {
        final generation = _generation();
        final categories = await live(client, priority: true);
        final items = await _mergeCategories(
          categories,
          (id) => liveStreams(client, id),
          (item) => item.streamId,
        );
        if (items.isEmpty) return;
        await CatalogStore.instance.replaceLive(
          scope,
          '*',
          items,
          generation: generation,
        );
        if (identical(_owner, client)) {
          _liveStreams['*'] = Future.value(items);
        }
      });

  Future<List<T>> _mergeCategories<T, K>(
    List<Category> categories,
    Future<List<T>> Function(String categoryId) fetch,
    K Function(T item) identity,
  ) async {
    final unique = <K, T>{};
    const batchSize = 4;
    for (var i = 0; i < categories.length; i += batchSize) {
      final batch = categories.skip(i).take(batchSize);
      final results = await Future.wait(
        batch.map((category) => fetch(category.id).catchError((_) => <T>[])),
      );
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
          '${value.categoryId}|${value.containerExtension}|${value.rating}',
    Series value =>
      '${value.seriesId}|${value.name}|${value.cover}|'
          '${value.categoryId}|${value.rating}|${value.releaseDate}',
    LiveStream value =>
      '${value.streamId}|${value.name}|${value.icon}|'
          '${value.categoryId}|${value.epgChannelId}|${value.tvArchive}',
    _ => '$item',
  };

  /// Returns the first non-empty result across a few attempts. Empty category
  /// lists are allowed after retrying (plain M3U profiles legitimately have no
  /// movie or series catalog).
  static Future<List<Category>?> _retry(
    Future<List<Category>> Function() fetch,
  ) async {
    for (var attempt = 0; attempt < 3; attempt++) {
      try {
        final result = await fetch();
        if (result.isNotEmpty) return result;
      } catch (_) {}
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
  final List<_ScheduledRequest<dynamic>> _priority = [];
  final List<_ScheduledRequest<dynamic>> _normal = [];

  Future<T> run<T>(Future<T> Function() task, {bool priority = false}) {
    final completer = Completer<T>();
    final request = _ScheduledRequest<T>(task, completer);
    (priority ? _priority : _normal).add(request);
    _drain();
    return completer.future;
  }

  void _drain() {
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
  _ScheduledRequest(this.task, this.completer);

  final Future<T> Function() task;
  final Completer<T> completer;

  Future<void> run() async {
    try {
      completer.complete(await task());
    } catch (error, stackTrace) {
      completer.completeError(error, stackTrace);
    }
  }
}
