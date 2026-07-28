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

    test('an explicitly secure-only channel can still reject HTTP', () {
      expect(
        providerTransportError(const [
          'http://provider.example:8080',
        ], requireSecureTransport: true),
        contains('HTTPS sources only'),
      );
      expect(
        isAllowedProviderUrl(
          'http://provider.example:8080',
          requireSecureTransport: true,
        ),
        isFalse,
      );
    });

    test('shipping builds accept user-supplied HTTP providers', () {
      expect(requiresSecureProviderTransport, isFalse);
      expect(
        providerTransportError(const ['http://provider.example:8080']),
        isNull,
      );
    });

    test('secure-only channels accept HTTPS providers', () {
      expect(
        providerTransportError(const [
          'https://provider.example:443',
        ], requireSecureTransport: true),
        isNull,
      );
    });
  });
}
