import 'dart:convert';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'models.dart';

/// Local persistence for the active login + saved profiles.
///
/// Stored in the iOS Keychain (via flutter_secure_storage), which survives app
/// uninstall/reinstall — so re-deploying a dev build doesn't force a re-login.
/// Also more secure than plaintext SharedPreferences.
class Store {
  static const _kActive = 'lumen_active';
  static const _kProfiles = 'lumen_profiles';
  static const _s = FlutterSecureStorage();

  static bool _migrated = false;

  /// One-time migration of any creds left in the old SharedPreferences store
  /// into the Keychain (so an existing login isn't lost on the next reinstall).
  static Future<void> _migrate() async {
    if (_migrated) return;
    _migrated = true;
    try {
      final p = await SharedPreferences.getInstance();
      for (final key in [_kActive, _kProfiles]) {
        final old = p.getString(key);
        if (old != null) {
          if (await _s.read(key: key) == null) await _s.write(key: key, value: old);
          await p.remove(key);
        }
      }
    } catch (_) {}
  }

  static Future<XtreamCredentials?> active() async {
    await _migrate();
    final raw = await _s.read(key: _kActive);
    if (raw == null) return null;
    try {
      return XtreamCredentials.fromJson(jsonDecode(raw));
    } catch (_) {
      return null;
    }
  }

  static Future<void> setActive(XtreamCredentials c) async {
    await _s.write(key: _kActive, value: jsonEncode(c.toJson()));
    // remember in profile list
    final profiles = await savedProfiles();
    if (!profiles.any((x) => x.baseUrl == c.baseUrl && x.username == c.username)) {
      profiles.insert(0, c);
      await _s.write(key: _kProfiles, value: jsonEncode(profiles.map((e) => e.toJson()).toList()));
    }
  }

  static Future<void> logout() async {
    await _s.delete(key: _kActive);
  }

  /// Remove a saved profile from the list (does not touch the active session).
  static Future<List<XtreamCredentials>> removeProfile(XtreamCredentials c) async {
    final profiles = await savedProfiles();
    profiles.removeWhere((x) => x.baseUrl == c.baseUrl && x.username == c.username);
    await _s.write(key: _kProfiles, value: jsonEncode(profiles.map((e) => e.toJson()).toList()));
    return profiles;
  }

  static Future<List<XtreamCredentials>> savedProfiles() async {
    await _migrate();
    final raw = await _s.read(key: _kProfiles);
    if (raw == null) return [];
    try {
      return (jsonDecode(raw) as List).map((e) => XtreamCredentials.fromJson(e)).toList();
    } catch (_) {
      return [];
    }
  }
}
