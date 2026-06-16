import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// A favouritable item (movie / series / live channel).
class MediaRef {
  final String kind; // 'movie' | 'series' | 'live'
  final int id; // streamId or seriesId
  final String name;
  final String image;
  final String url; // direct play url (used for live channels)
  const MediaRef({required this.kind, required this.id, required this.name, this.image = '', this.url = ''});
  bool get isLive => kind == 'live';
  String get key => '$kind:$id';
  Map<String, dynamic> toJson() => {'kind': kind, 'id': id, 'name': name, 'image': image, 'url': url};
  factory MediaRef.fromJson(Map<String, dynamic> j) =>
      MediaRef(kind: j['kind'], id: j['id'], name: j['name'], image: j['image'] ?? '', url: j['url'] ?? '');
}

/// Saved playback progress for continue-watching.
class Progress {
  final String key; // 'movie:123' | 'ep:456'
  final String title;
  final String poster;
  final String url;
  final String ext;
  final int position; // seconds
  final int duration; // seconds
  final int updatedAt;
  const Progress({
    required this.key,
    required this.title,
    required this.poster,
    required this.url,
    required this.ext,
    required this.position,
    required this.duration,
    required this.updatedAt,
  });
  double get fraction => duration > 0 ? (position / duration).clamp(0, 1) : 0;
  Map<String, dynamic> toJson() =>
      {'key': key, 'title': title, 'poster': poster, 'url': url, 'ext': ext, 'p': position, 'd': duration, 't': updatedAt};
  factory Progress.fromJson(Map<String, dynamic> j) => Progress(
        key: j['key'],
        title: j['title'] ?? '',
        poster: j['poster'] ?? '',
        url: j['url'] ?? '',
        ext: j['ext'] ?? '',
        position: j['p'] ?? 0,
        duration: j['d'] ?? 0,
        updatedAt: j['t'] ?? 0,
      );
}

/// Persistent user library: favourites, continue-watching, recently-watched.
class Library extends ChangeNotifier {
  Library._();
  static final Library instance = Library._();

  static const _kFav = 'lib_favourites';
  static const _kProg = 'lib_progress';
  static const _kRecent = 'lib_recent';

  final List<MediaRef> favourites = [];
  final Map<String, Progress> progress = {};
  final List<MediaRef> recent = [];

  Future<void> load() async {
    final p = await SharedPreferences.getInstance();
    _readList(p.getString(_kFav), favourites);
    _readList(p.getString(_kRecent), recent);
    progress.clear();
    final pr = p.getString(_kProg);
    if (pr != null) {
      try {
        (jsonDecode(pr) as Map).forEach((k, v) => progress[k] = Progress.fromJson((v as Map).cast<String, dynamic>()));
      } catch (_) {}
    }
    notifyListeners();
  }

  void _readList(String? raw, List<MediaRef> into) {
    into.clear();
    if (raw == null) return;
    try {
      for (final e in jsonDecode(raw) as List) {
        into.add(MediaRef.fromJson((e as Map).cast<String, dynamic>()));
      }
    } catch (_) {}
  }

  Future<void> _save() async {
    final p = await SharedPreferences.getInstance();
    p.setString(_kFav, jsonEncode(favourites.map((e) => e.toJson()).toList()));
    p.setString(_kRecent, jsonEncode(recent.map((e) => e.toJson()).toList()));
    p.setString(_kProg, jsonEncode(progress.map((k, v) => MapEntry(k, v.toJson()))));
  }

  // ---- favourites ----
  bool isFav(String key) => favourites.any((e) => e.key == key);
  void toggleFav(MediaRef ref) {
    final i = favourites.indexWhere((e) => e.key == ref.key);
    if (i >= 0) {
      favourites.removeAt(i);
    } else {
      favourites.insert(0, ref);
    }
    notifyListeners();
    _save();
  }

  // ---- continue watching ----
  void saveProgress(Progress pr) {
    // drop items that are essentially finished
    if (pr.duration > 0 && pr.position / pr.duration > 0.95) {
      progress.remove(pr.key);
    } else if (pr.position > 10) {
      progress[pr.key] = pr;
    } else {
      return;
    }
    notifyListeners();
    _save();
  }

  void clearProgress(String key) {
    if (progress.remove(key) != null) {
      notifyListeners();
      _save();
    }
  }

  List<Progress> continueWatching() {
    final l = progress.values.where((e) => e.duration > 0 && e.position > 10).toList();
    l.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    return l;
  }

  // ---- recently watched ----
  void addRecent(MediaRef ref) {
    recent.removeWhere((e) => e.key == ref.key);
    recent.insert(0, ref);
    if (recent.length > 24) recent.removeRange(24, recent.length);
    notifyListeners();
    _save();
  }
}
