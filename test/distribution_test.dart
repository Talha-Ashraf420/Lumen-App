import 'package:flutter_test/flutter_test.dart';
import 'package:lumen_tv/distribution.dart';

void main() {
  group('provider transport policy', () {
    test('shipping builds accept user-supplied HTTP providers', () {
      expect(isAllowedProviderUrl('http://provider.example:8080'), isTrue);
    });

    test('shipping builds accept HTTPS providers', () {
      expect(isAllowedProviderUrl('https://provider.example:443'), isTrue);
    });

    test('other URL schemes remain blocked', () {
      expect(isAllowedProviderUrl('ftp://provider.example/library'), isFalse);
      expect(isAllowedProviderUrl('provider.example'), isFalse);
    });
  });
}
