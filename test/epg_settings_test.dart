import 'package:flutter_test/flutter_test.dart';
import 'package:lumen_tv/epg_settings.dart';
import 'package:lumen_tv/models.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  const first = XtreamCredentials(
    baseUrl: 'https://one.example',
    username: 'one',
    password: 'secret',
  );
  const second = XtreamCredentials(
    baseUrl: 'https://two.example',
    username: 'two',
    password: 'secret',
  );

  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('settings are private to each provider profile', () async {
    await EpgSettings.save(
      first,
      manualUrl: 'https://guide.example/one.xml',
      offsetMinutes: 90,
    );

    final saved = await EpgSettings.load(first);
    final untouched = await EpgSettings.load(second);

    expect(saved.manualUrl, 'https://guide.example/one.xml');
    expect(saved.offsetMinutes, 90);
    expect(untouched.manualUrl, isEmpty);
    expect(untouched.offsetMinutes, 0);
  });

  test('manual source accepts only complete HTTP and HTTPS URLs', () {
    expect(EpgSettings.validateManualUrl(''), isNull);
    expect(
      EpgSettings.validateManualUrl('https://guide.example/epg.xml'),
      isNull,
    );
    expect(
      EpgSettings.validateManualUrl('ftp://guide.example/epg.xml'),
      isNotNull,
    );
    expect(EpgSettings.validateManualUrl('guide.xml'), isNotNull);
  });

  test('saving settings notifies open guide repositories', () async {
    final before = epgConfigurationRevision.value;
    await EpgSettings.save(first, manualUrl: '', offsetMinutes: -60);
    expect(epgConfigurationRevision.value, before + 1);
  });
}
