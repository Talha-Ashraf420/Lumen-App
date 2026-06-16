import 'package:flutter_test/flutter_test.dart';
import 'package:lumen_tv/xtream.dart';

void main() {
  test('normalizeBaseUrl adds scheme and strips trailing path', () {
    expect(normalizeBaseUrl('host.com:8080'), 'http://host.com:8080');
    expect(normalizeBaseUrl('http://host.com:8080/player_api.php'), 'http://host.com:8080');
  });
}
