import 'dart:io' show Platform;
import 'package:flutter/foundation.dart';

/// True only for the Android App Bundle submitted to Google Play.
///
/// Android TV APKs distributed directly are a separate channel because many
/// user-authorized IPTV providers still expose HTTP-only endpoints. Play
/// bundles must opt in with:
/// `--dart-define=GOOGLE_PLAY_BUILD=true`.
const bool isGooglePlayBuild = bool.fromEnvironment(
  'GOOGLE_PLAY_BUILD',
  defaultValue: false,
);

bool get requiresSecureProviderTransport =>
    !kIsWeb && Platform.isAndroid && isGooglePlayBuild;

bool isAllowedProviderUrl(String value, {bool? requireSecureTransport}) {
  final uri = Uri.tryParse(value.trim());
  if (uri == null || uri.host.isEmpty) return false;
  final secureOnly = requireSecureTransport ?? requiresSecureProviderTransport;
  if (secureOnly) return uri.scheme.toLowerCase() == 'https';
  return uri.scheme == 'https' || uri.scheme == 'http';
}

String? providerTransportError(
  Iterable<String?> values, {
  bool? requireSecureTransport,
}) {
  final secureOnly = requireSecureTransport ?? requiresSecureProviderTransport;
  if (!secureOnly) return null;
  for (final value in values) {
    if (value == null || value.trim().isEmpty) continue;
    if (!isAllowedProviderUrl(value, requireSecureTransport: true)) {
      return 'For your security, the Google Play build accepts HTTPS sources only.';
    }
  }
  return null;
}
