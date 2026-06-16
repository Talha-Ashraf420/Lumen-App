import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// A single shelf the user chose to show on Home (a category/playlist).
class ShelfRef {
  final String type; // 'movie' | 'series' | 'live'
  final String id; // category id
  final String name;
  const ShelfRef(this.type, this.id, this.name);
  String get key => '$type:$id';
  Map<String, dynamic> toJson() => {'t': type, 'id': id, 'name': name};
  factory ShelfRef.fromJson(Map<String, dynamic> j) =>
      ShelfRef(j['t'] ?? 'movie', '${j['id']}', j['name'] ?? '');
}

/// User-customised Home layout. When empty, Home falls back to its default mix.
class HomeConfig extends ChangeNotifier {
  HomeConfig._();
  static final HomeConfig instance = HomeConfig._();
  static const _k = 'home_shelves';

  final List<ShelfRef> shelves = [];
  bool get isCustom => shelves.isNotEmpty;

  Future<void> load() async {
    final p = await SharedPreferences.getInstance();
    final raw = p.getString(_k);
    shelves.clear();
    if (raw != null) {
      try {
        for (final e in jsonDecode(raw) as List) {
          shelves.add(ShelfRef.fromJson((e as Map).cast<String, dynamic>()));
        }
      } catch (_) {}
    }
    notifyListeners();
  }

  bool isEnabled(String type, String id) => shelves.any((s) => s.type == type && s.id == id);

  void toggle(ShelfRef ref) {
    final i = shelves.indexWhere((s) => s.key == ref.key);
    if (i >= 0) {
      shelves.removeAt(i);
    } else {
      shelves.add(ref);
    }
    notifyListeners();
    _save();
  }

  void reorder(int oldIndex, int newIndex) {
    if (newIndex > oldIndex) newIndex--;
    final item = shelves.removeAt(oldIndex);
    shelves.insert(newIndex, item);
    notifyListeners();
    _save();
  }

  void clear() {
    shelves.clear();
    notifyListeners();
    _save();
  }

  Future<void> _save() async {
    final p = await SharedPreferences.getInstance();
    await p.setString(_k, jsonEncode(shelves.map((e) => e.toJson()).toList()));
  }
}
