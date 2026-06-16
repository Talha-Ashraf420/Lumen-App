import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'models.dart';

/// Local persistence for the active login + saved profiles.
class Store {
  static const _kActive = 'lumen_active';
  static const _kProfiles = 'lumen_profiles';

  static Future<XtreamCredentials?> active() async {
    final p = await SharedPreferences.getInstance();
    final raw = p.getString(_kActive);
    if (raw == null) return null;
    try {
      return XtreamCredentials.fromJson(jsonDecode(raw));
    } catch (_) {
      return null;
    }
  }

  static Future<void> setActive(XtreamCredentials c) async {
    final p = await SharedPreferences.getInstance();
    await p.setString(_kActive, jsonEncode(c.toJson()));
    // remember in profile list
    final profiles = await savedProfiles();
    if (!profiles.any((x) => x.baseUrl == c.baseUrl && x.username == c.username)) {
      profiles.insert(0, c);
      await p.setString(_kProfiles, jsonEncode(profiles.map((e) => e.toJson()).toList()));
    }
  }

  static Future<void> logout() async {
    final p = await SharedPreferences.getInstance();
    await p.remove(_kActive);
  }

  static Future<List<XtreamCredentials>> savedProfiles() async {
    final p = await SharedPreferences.getInstance();
    final raw = p.getString(_kProfiles);
    if (raw == null) return [];
    try {
      return (jsonDecode(raw) as List).map((e) => XtreamCredentials.fromJson(e)).toList();
    } catch (_) {
      return [];
    }
  }
}
