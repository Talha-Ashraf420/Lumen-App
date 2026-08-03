/// Lumen accepts both HTTP and HTTPS because many user-authorized legacy media
/// providers do not offer TLS. HTTPS remains strongly recommended, but every
/// shipping channel follows the same user-supplied provider policy.
bool isAllowedProviderUrl(String value) {
  final uri = Uri.tryParse(value.trim());
  if (uri == null || uri.host.isEmpty) return false;
  final scheme = uri.scheme.toLowerCase();
  return scheme == 'https' || scheme == 'http';
}
