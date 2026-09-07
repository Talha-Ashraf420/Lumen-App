import 'package:flutter_test/flutter_test.dart';
import 'package:lumen_tv/legal.dart';

void main() {
  test('community link uses a secure Discord invite', () {
    final uri = Uri.parse(communityUrl);

    expect(uri.scheme, 'https');
    expect(uri.host, 'discord.gg');
    expect(uri.pathSegments, isNotEmpty);
  });
}
