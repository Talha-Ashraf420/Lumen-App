import 'package:flutter_test/flutter_test.dart';
import 'package:lumen_tv/epg_cache.dart';
import 'package:lumen_tv/models.dart';
import 'package:lumen_tv/xtream.dart';

class _FakeXtreamClient extends XtreamClient {
  _FakeXtreamClient()
    : super(
        const XtreamCredentials(
          baseUrl: 'https://example.test',
          username: 'user',
          password: 'pass',
        ),
      );

  int calls = 0;
  bool failNext = false;
  List<EpgEntry> response = const [];

  @override
  Future<List<EpgEntry>> shortEpg(int streamId, {int limit = 4}) async {
    calls++;
    if (failNext) {
      failNext = false;
      throw XtreamException('temporary');
    }
    return response;
  }
}

void main() {
  setUp(EpgCache.instance.clear);

  test('does not cache a failed EPG request', () async {
    final client = _FakeXtreamClient()..failNext = true;
    await expectLater(
      EpgCache.instance.nowNext(client, 1),
      throwsA(isA<XtreamException>()),
    );
    await EpgCache.instance.nowNext(client, 1);
    expect(client.calls, 2);
  });

  test('does not cache an empty EPG response', () async {
    final client = _FakeXtreamClient();
    await EpgCache.instance.nowNext(client, 1);
    await EpgCache.instance.nowNext(client, 1);
    expect(client.calls, 2);
  });

  test('scopes cache entries to the provider client', () async {
    final first = _FakeXtreamClient();
    final second = _FakeXtreamClient();
    await EpgCache.instance.nowNext(first, 7);
    await EpgCache.instance.nowNext(second, 7);
    expect(first.calls, 1);
    expect(second.calls, 1);
  });
}
