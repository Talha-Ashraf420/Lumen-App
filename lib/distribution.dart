/// Lumen accepts both HTTP and HTTPS because many user-authorized legacy media
/// providers do not offer TLS. HTTPS remains strongly recommended, but the app
/// must not reject a source the user explicitly supplies.
bool get requiresSecureProviderTransport => false;

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
      return 'This distribution channel accepts HTTPS sources only.';
    }
  }
  return null;
}
