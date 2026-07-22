import 'dart:async';
import 'models.dart';
import 'xtream.dart';

/// In-memory EPG cache with a small concurrency gate. The guide's
/// ListView.builder lazily builds rows, so only on-screen channels fetch — each
/// fetch is memoized per streamId (re-scroll is instant) and at most a few run
/// at once, so we never burst the provider.
class EpgCache {
  EpgCache._();
  static final EpgCache instance = EpgCache._();

  final Map<(XtreamClient, int), _EpgCacheEntry> _nowNext = {};
  final Map<(XtreamClient, int), _EpgCacheEntry> _fullDay = {};
  final _gate = _Gate(3);

  Future<List<EpgEntry>> nowNext(XtreamClient c, int streamId) {
    return _cached(
      _nowNext,
      (c, streamId),
      const Duration(minutes: 2),
      () => c.shortEpg(streamId, limit: 2),
    );
  }

  Future<List<EpgEntry>> fullDay(XtreamClient c, int streamId) {
    return _cached(
      _fullDay,
      (c, streamId),
      const Duration(minutes: 15),
      () => c.simpleDataTable(streamId),
    );
  }

  Future<List<EpgEntry>> _cached(
    Map<(XtreamClient, int), _EpgCacheEntry> cache,
    (XtreamClient, int) key,
    Duration ttl,
    Future<List<EpgEntry>> Function() fetch,
  ) {
    final now = DateTime.now();
    final existing = cache[key];
    if (existing != null && now.difference(existing.createdAt) < ttl) {
      return existing.value;
    }
    late final Future<List<EpgEntry>> future;
    future = () async {
      try {
        final value = await _gate.run(fetch);
        // An empty guide is often a transient provider response. Return it to
        // the current caller but do not make it sticky.
        if (value.isEmpty && identical(cache[key]?.value, future))
          cache.remove(key);
        return value;
      } catch (_) {
        if (identical(cache[key]?.value, future)) cache.remove(key);
        rethrow;
      }
    }();
    cache[key] = _EpgCacheEntry(now, future);
    return future;
  }

  void clear() {
    _nowNext.clear();
    _fullDay.clear();
  }
}

class _EpgCacheEntry {
  final DateTime createdAt;
  final Future<List<EpgEntry>> value;
  const _EpgCacheEntry(this.createdAt, this.value);
}

/// A tiny counting semaphore to cap concurrent EPG requests.
class _Gate {
  final int max;
  int _active = 0;
  final _waiters = <Completer<void>>[];
  _Gate(this.max);

  Future<T> run<T>(Future<T> Function() task) async {
    await _acquire();
    try {
      return await task();
    } finally {
      _release();
    }
  }

  Future<void> _acquire() {
    if (_active < max) {
      _active++;
      return Future.value();
    }
    final c = Completer<void>();
    _waiters.add(c);
    return c.future;
  }

  void _release() {
    if (_waiters.isNotEmpty) {
      _waiters.removeAt(0).complete();
    } else {
      _active--;
    }
  }
}
