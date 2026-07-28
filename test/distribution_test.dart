import 'package:flutter_test/flutter_test.dart';
import 'package:lumen_tv/distribution.dart';

void main() {
  group('provider transport policy', () {
    test('direct Android builds accept authorized HTTP providers', () {
      expect(
        providerTransportError(const [
          'http://provider.example:8080',
        ], requireSecureTransport: false),
        isNull,
      );
      expect(
        isAllowedProviderUrl(
          'http://provider.example:8080',
          requireSecureTransport: false,
        ),
        isTrue,
      );
    });

    test('Google Play builds reject HTTP providers', () {
      expect(
        providerTransportError(const [
          'http://provider.example:8080',
        ], requireSecureTransport: true),
        contains('Google Play build'),
      );
      expect(
        isAllowedProviderUrl(
          'http://provider.example:8080',
          requireSecureTransport: true,
        ),
        isFalse,
      );
    });

    test('Google Play builds accept HTTPS providers', () {
      expect(
        providerTransportError(const [
          'https://provider.example:443',
        ], requireSecureTransport: true),
        isNull,
      );
    });
  });
}
