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

  final Map<int, Future<List<EpgEntry>>> _nowNext = {};
  final Map<int, Future<List<EpgEntry>>> _fullDay = {};
  final _gate = _Gate(3);

  Future<List<EpgEntry>> nowNext(XtreamClient c, int streamId) {
    return _nowNext.putIfAbsent(
      streamId,
      () => _gate.run(() => c.shortEpg(streamId, limit: 2)).catchError((_) => <EpgEntry>[]),
    );
  }

  Future<List<EpgEntry>> fullDay(XtreamClient c, int streamId) {
    return _fullDay.putIfAbsent(
      streamId,
      () => _gate.run(() => c.simpleDataTable(streamId)).catchError((_) => <EpgEntry>[]),
    );
  }

  void clear() {
    _nowNext.clear();
    _fullDay.clear();
  }
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
