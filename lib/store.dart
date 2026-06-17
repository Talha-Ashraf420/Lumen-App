import 'dart:convert';
import 'dart:io' show Platform;
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'models.dart';

/// Local persistence for the active login + saved profiles.
///
/// On iOS the credentials live in the Keychain (survives uninstall, more
/// secure). On macOS/desktop the Keychain needs entitlements a local build
/// doesn't have (error -34018), so we use SharedPreferences there instead.
class Store {
  static const _kActive = 'lumen_active';
  static const _kProfiles = 'lumen_profiles';
  static const _secure = FlutterSecureStorage();
  static final bool _useSecure = !kIsWeb && Platform.isIOS;

  static bool _migrated = false;

  static Future<String?> _read(String key) async {
    if (_useSecure) return _secure.read(key: key);
    final p = await SharedPreferences.getInstance();
    return p.getString(key);
  }

  static Future<void> _write(String key, String value) async {
    if (_useSecure) return _secure.write(key: key, value: value);
    final p = await SharedPreferences.getInstance();
    await p.setString(key, value);
  }

  static Future<void> _delete(String key) async {
    if (_useSecure) return _secure.delete(key: key);
    final p = await SharedPreferences.getInstance();
    await p.remove(key);
  }

  /// One-time migration of creds left in the old SharedPreferences store into
  /// the Keychain (iOS only — on desktop prefs already is the store).
  static Future<void> _migrate() async {
    if (_migrated) return;
    _migrated = true;
    if (!_useSecure) return;
    try {
      final p = await SharedPreferences.getInstance();
      for (final key in [_kActive, _kProfiles]) {
        final old = p.getString(key);
        if (old != null) {
          if (await _secure.read(key: key) == null) await _secure.write(key: key, value: old);
          await p.remove(key);
        }
      }
    } catch (_) {}
  }

  static Future<XtreamCredentials?> active() async {
    await _migrate();
    final raw = await _read(_kActive);
    if (raw == null) return null;
    try {
      return XtreamCredentials.fromJson(jsonDecode(raw));
    } catch (_) {
      return null;
    }
  }

  static Future<void> setActive(XtreamCredentials c) async {
    await _write(_kActive, jsonEncode(c.toJson()));
    final profiles = await savedProfiles();
    if (!profiles.any((x) => x.baseUrl == c.baseUrl && x.username == c.username)) {
      profiles.insert(0, c);
      await _write(_kProfiles, jsonEncode(profiles.map((e) => e.toJson()).toList()));
    }
  }

  static Future<void> logout() async {
    await _delete(_kActive);
  }

  static Future<List<XtreamCredentials>> removeProfile(XtreamCredentials c) async {
    final profiles = await savedProfiles();
    profiles.removeWhere((x) => x.baseUrl == c.baseUrl && x.username == c.username);
    await _write(_kProfiles, jsonEncode(profiles.map((e) => e.toJson()).toList()));
    return profiles;
  }

  static Future<List<XtreamCredentials>> savedProfiles() async {
    await _migrate();
    final raw = await _read(_kProfiles);
    if (raw == null) return [];
    try {
      return (jsonDecode(raw) as List).map((e) => XtreamCredentials.fromJson(e)).toList();
    } catch (_) {
      return [];
    }
  }
}
