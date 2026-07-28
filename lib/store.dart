import 'dart:async';
import 'dart:convert';
import 'dart:io' show Platform;
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'catalog_store.dart';
import 'models.dart';

/// Local persistence for the active login + saved profiles.
///
/// On Android and iOS sensitive values live in encrypted platform storage.
/// Desktop builds use SharedPreferences because local macOS builds may not have
/// the Keychain entitlements required by flutter_secure_storage.
class Store {
  static const _kActive = 'lumen_active';
  static const _kProfiles = 'lumen_profiles';
  static const _kSignedOut = 'lumen_signed_out';
  static const _secure = FlutterSecureStorage();
  static final bool _useSecure =
      !kIsWeb && (Platform.isAndroid || Platform.isIOS);

  static bool _migrated = false;

  /// Stable, non-secret namespace for state belonging to one provider profile.
  ///
  /// Credentials and tokenised M3U URLs must never become part of a preference
  /// key. FNV-1a is sufficient here: this is a namespace, not authentication.
  static String profileScope(XtreamCredentials credentials) {
    final identity = credentials.isDemo
        ? 'demo|lumen-offline-v1'
        : credentials.isM3u
        ? 'm3u|${credentials.m3uUrl?.trim() ?? ''}'
        : 'xtream|${credentials.baseUrl.trim().toLowerCase()}|'
              '${credentials.username.trim()}';
    var hash = 0x811c9dc5;
    for (final byte in utf8.encode(identity)) {
      hash ^= byte;
      hash = (hash * 0x01000193) & 0xffffffff;
    }
    return hash.toRadixString(16).padLeft(8, '0');
  }

  static String scopedKey(String key, XtreamCredentials credentials) =>
      '${key}_${profileScope(credentials)}';

  static bool sameProfile(XtreamCredentials a, XtreamCredentials b) =>
      profileScope(a) == profileScope(b);

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

  /// Encrypted persistence for app state that may contain tokenized media URLs.
  /// Old SharedPreferences values are migrated on first read.
  static Future<String?> readPrivate(String key) async {
    if (!_useSecure) return _read(key);
    try {
      final secureValue = await _secure.read(key: key);
      if (secureValue != null) return secureValue;
      final preferences = await SharedPreferences.getInstance();
      final legacyValue = preferences.getString(key);
      if (legacyValue != null) {
        await _secure.write(key: key, value: legacyValue);
        await preferences.remove(key);
      }
      return legacyValue;
    } catch (_) {
      return null;
    }
  }

  static Future<void> writePrivate(String key, String value) =>
      _write(key, value);

  static Future<void> deletePrivate(String key) => _delete(key);

  /// One-time migration of creds left in the old SharedPreferences store into
  /// encrypted platform storage (Android/iOS only).
  static Future<void> _migrate() async {
    if (_migrated) return;
    _migrated = true;
    if (!_useSecure) return;
    try {
      final p = await SharedPreferences.getInstance();
      for (final key in [_kActive, _kProfiles]) {
        final old = p.getString(key);
        if (old != null) {
          if (await _secure.read(key: key) == null)
            await _secure.write(key: key, value: old);
          await p.remove(key);
        }
      }
    } catch (_) {}
  }

  static Future<XtreamCredentials?> active() async {
    await _migrate();
    final preferences = await SharedPreferences.getInstance();
    // This non-sensitive tombstone is intentionally outside secure storage.
    // Some Android keystore implementations finish a delete slowly; the
    // tombstone makes sign-out authoritative immediately and prevents a stale
    // encrypted credential from restoring the session after a quick restart.
    if (preferences.getBool(_kSignedOut) ?? false) return null;
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
    final preferences = await SharedPreferences.getInstance();
    await preferences.setBool(_kSignedOut, false);
    final profiles = await savedProfiles();
    if (!profiles.any((x) => sameProfile(x, c))) {
      profiles.insert(0, c);
      await _write(
        _kProfiles,
        jsonEncode(profiles.map((e) => e.toJson()).toList()),
      );
    }
  }

  static Future<void> logout() async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.setBool(_kSignedOut, true);
    // The marker above is the source of truth. Remove the encrypted payload as
    // best-effort cleanup without holding the UI on a loader.
    unawaited(
      _delete(_kActive).timeout(const Duration(seconds: 3)).catchError((
        Object error,
      ) {
        debugPrint('Secure credential cleanup was deferred: $error');
      }),
    );
  }

  static Future<List<XtreamCredentials>> removeProfile(
    XtreamCredentials c,
  ) async {
    final profiles = await savedProfiles();
    profiles.removeWhere((x) => sameProfile(x, c));
    await _write(
      _kProfiles,
      jsonEncode(profiles.map((e) => e.toJson()).toList()),
    );
    // If we removed the currently-active account, clear the active session too —
    // otherwise it silently persists and signs back in on the next launch.
    final act = await active();
    if (act != null && sameProfile(act, c)) {
      await _delete(_kActive);
    }
    // Removing an account also erases its indexed browse metadata. The
    // generation tombstone prevents any older in-flight provider request from
    // recreating rows after this point.
    await CatalogStore.instance.deleteProfile(profileScope(c));
    return profiles;
  }

  static Future<List<XtreamCredentials>> savedProfiles() async {
    await _migrate();
    final raw = await _read(_kProfiles);
    if (raw == null) return [];
    try {
      return (jsonDecode(raw) as List)
          .map((e) => XtreamCredentials.fromJson(e))
          .toList();
    } catch (_) {
      return [];
    }
  }
}
