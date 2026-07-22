import 'dart:io' show Platform;
import 'package:flutter/foundation.dart';

bool get requiresSecureProviderTransport => !kIsWeb && Platform.isAndroid;

bool isAllowedProviderUrl(String value) {
  final uri = Uri.tryParse(value.trim());
  if (uri == null || uri.host.isEmpty) return false;
  if (requiresSecureProviderTransport) return uri.scheme == 'https';
  return uri.scheme == 'https' || uri.scheme == 'http';
}

String? providerTransportError(Iterable<String?> values) {
  if (!requiresSecureProviderTransport) return null;
  for (final value in values) {
    if (value == null || value.trim().isEmpty) continue;
    if (!isAllowedProviderUrl(value)) {
      return 'For your security, the Google Play build accepts HTTPS sources only.';
    }
  }
  return null;
}
