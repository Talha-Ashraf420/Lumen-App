import 'dart:async';

import 'models.dart';
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

  Future<List<Category>>? _vodCategories;
  Future<List<Category>>? _seriesCategories;
  Future<List<Category>>? _liveCategories;

  final Map<String, Future<List<VodStream>>> _vodStreams = {};
  final Map<String, Future<List<Series>>> _series = {};
  final Map<String, Future<List<LiveStream>>> _liveStreams = {};
  final Map<int, Future<VodInfo>> _vodInfo = {};
  final Map<int, Future<SeriesInfo>> _seriesInfo = {};

  Future<List<Category>> vod(XtreamClient client, {bool priority = false}) {
    _ensureOwner(client);
    return _vodCategories ??= _loadCategories(
      client.vodCategories,
      priority: priority,
    );
  }

  Future<List<Category>> series(XtreamClient client, {bool priority = false}) {
    _ensureOwner(client);
    return _seriesCategories ??= _loadCategories(
      client.seriesCategories,
      priority: priority,
    );
  }

  Future<List<Category>> live(XtreamClient client, {bool priority = false}) {
    _ensureOwner(client);
    return _liveCategories ??= _loadCategories(
      client.liveCategories,
      priority: priority,
    );
  }

  Future<List<VodStream>> vodStreams(
    XtreamClient client,
    String? categoryId, {
    bool priority = false,
  }) {
    _ensureOwner(client);
    return _memoized(
      _vodStreams,
      categoryId ?? '*',
      () => _requests.run(
        () => client.vodStreams(categoryId),
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
    return _memoized(
      _series,
      categoryId ?? '*',
      () => _requests.run(() => client.series(categoryId), priority: priority),
    );
  }

  Future<List<LiveStream>> liveStreams(
    XtreamClient client,
    String? categoryId, {
    bool priority = false,
  }) {
    _ensureOwner(client);
    return _memoized(
      _liveStreams,
      categoryId ?? '*',
      () => _requests.run(
        () => client.liveStreams(categoryId),
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
    _vodCategories = null;
    _seriesCategories = null;
    _liveCategories = null;
    _vodStreams.clear();
    _series.clear();
    _liveStreams.clear();
    _vodInfo.clear();
    _seriesInfo.clear();
  }

  Future<List<Category>> _loadCategories(
    Future<List<Category>> Function() fetch, {
    bool priority = false,
  }) async =>
      (await _retry(() => _requests.run(fetch, priority: priority))) ??
      const [];

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
