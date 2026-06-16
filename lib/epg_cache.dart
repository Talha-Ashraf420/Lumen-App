import 'models.dart';
import 'xtream.dart';

/// In-memory EPG cache. The guide's ListView.builder lazily builds rows, so only
/// on-screen channels fetch — and each fetch is memoized per streamId, making
/// re-scroll instant and avoiding a request storm.
class EpgCache {
  EpgCache._();
  static final EpgCache instance = EpgCache._();

  final Map<int, Future<List<EpgEntry>>> _nowNext = {};
  final Map<int, Future<List<EpgEntry>>> _fullDay = {};

  Future<List<EpgEntry>> nowNext(XtreamClient c, int streamId) {
    return _nowNext.putIfAbsent(
      streamId,
      () => c.shortEpg(streamId, limit: 2).catchError((_) => <EpgEntry>[]),
    );
  }

  Future<List<EpgEntry>> fullDay(XtreamClient c, int streamId) {
    return _fullDay.putIfAbsent(
      streamId,
      () => c.simpleDataTable(streamId).catchError((_) => <EpgEntry>[]),
    );
  }

  void clear() {
    _nowNext.clear();
    _fullDay.clear();
  }
}
