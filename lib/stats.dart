import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Accumulated watch statistics for the "Your Lumen" screen. Time is added in
/// small increments by the playback controller while something is playing.
class WatchStats extends ChangeNotifier {
  WatchStats._();
  static final WatchStats instance = WatchStats._();
  static const _k = 'watch_stats_v1';

  int total = 0; // seconds
  int movie = 0, series = 0, live = 0; // seconds by kind
  final Map<String, int> byCategory = {}; // categoryId -> seconds
  final Map<String, int> byDay = {}; // 'yyyy-mm-dd' -> seconds
  final Set<String> _titles = {}; // distinct items watched

  int get titleCount => _titles.length;

  Future<void> load() async {
    final p = await SharedPreferences.getInstance();
    final raw = p.getString(_k);
    if (raw != null) {
      try {
        final j = jsonDecode(raw) as Map<String, dynamic>;
        total = j['total'] ?? 0;
        movie = j['movie'] ?? 0;
        series = j['series'] ?? 0;
        live = j['live'] ?? 0;
        byCategory.clear();
        (j['cats'] as Map?)?.forEach((k, v) => byCategory['$k'] = v as int);
        byDay.clear();
        (j['days'] as Map?)?.forEach((k, v) => byDay['$k'] = v as int);
        _titles
          ..clear()
          ..addAll(((j['titles'] as List?) ?? []).map((e) => '$e'));
      } catch (_) {}
    }
    notifyListeners();
  }

  /// Add [seconds] of playback. [day] is the local 'yyyy-mm-dd' (passed in to
  /// keep this testable / time-source-free).
  void add({required int seconds, required String kind, required String cat, required String titleKey, required String day}) {
    total += seconds;
    switch (kind) {
      case 'series':
        series += seconds;
      case 'live':
        live += seconds;
      default:
        movie += seconds;
    }
    if (cat.isNotEmpty) byCategory[cat] = (byCategory[cat] ?? 0) + seconds;
    byDay[day] = (byDay[day] ?? 0) + seconds;
    // keep only the last ~14 days
    if (byDay.length > 14) {
      final keys = byDay.keys.toList()..sort();
      for (final k in keys.take(byDay.length - 14)) {
        byDay.remove(k);
      }
    }
    if (titleKey.isNotEmpty) _titles.add(titleKey);
    notifyListeners();
    _save();
  }

  void reset() {
    total = movie = series = live = 0;
    byCategory.clear();
    byDay.clear();
    _titles.clear();
    notifyListeners();
    _save();
  }

  Future<void> _save() async {
    final p = await SharedPreferences.getInstance();
    await p.setString(
      _k,
      jsonEncode({
        'total': total,
        'movie': movie,
        'series': series,
        'live': live,
        'cats': byCategory,
        'days': byDay,
        'titles': _titles.toList(),
      }),
    );
  }
}
