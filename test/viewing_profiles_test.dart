import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lumen_tv/home_config.dart';
import 'package:lumen_tv/library.dart';
import 'package:lumen_tv/models.dart';
import 'package:lumen_tv/screens/viewer_picker_screen.dart';
import 'package:lumen_tv/stats.dart';
import 'package:lumen_tv/store.dart';
import 'package:lumen_tv/viewing_profiles.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _service = XtreamCredentials(
  baseUrl: 'https://one.example',
  username: 'test',
  password: 'secret',
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await ViewingProfiles.instance.load();
    await Library.instance.activate(null);
    await HomeConfig.instance.activate(null);
    await WatchStats.instance.activate(null);
  });

  test('existing viewer data remains on the default storage keys', () async {
    final key = Store.scopedKey('lib_favourites', _service);
    await Store.writePrivate(
      key,
      '[{"kind":"movie","id":7,"name":"Existing favorite"}]',
    );
    await Library.instance.activate(_service);
    expect(Library.instance.favourites.single.name, 'Existing favorite');
    expect(Store.viewingScopedKey('lib_favourites', _service, 'default'), key);
  });

  test('two viewers keep activity separate on the same service', () async {
    await Store.setActive(_service);
    final second = await ViewingProfiles.instance.add('Sam');
    await Library.instance.activate(_service);
    Library.instance.toggleFav(
      const MediaRef(kind: 'movie', id: 1, name: 'First movie'),
    );
    Library.instance.saveProgress(
      const Progress(
        key: 'movie:1',
        title: 'First movie',
        poster: '',
        url: '',
        ext: 'mp4',
        position: 60,
        duration: 600,
        updatedAt: 1,
      ),
    );
    await HomeConfig.instance.activate(_service);
    HomeConfig.instance.toggle(const ShelfRef('movie', '1', 'First shelf'));
    await WatchStats.instance.activate(_service);
    WatchStats.instance.add(
      seconds: 30,
      kind: 'movie',
      cat: '1',
      titleKey: 'movie:1',
      day: '2026-09-17',
    );
    await Future<void>.delayed(const Duration(milliseconds: 30));

    await Future.wait([
      Library.instance.activate(_service, viewingId: second.id),
      HomeConfig.instance.activate(_service, viewingId: second.id),
      WatchStats.instance.activate(_service, viewingId: second.id),
    ]);
    expect(Library.instance.favourites, isEmpty);
    expect(Library.instance.continueWatching(), isEmpty);
    expect(HomeConfig.instance.shelves, isEmpty);
    expect(WatchStats.instance.total, 0);

    Library.instance.toggleFav(
      const MediaRef(kind: 'live', id: 2, name: 'Sam channel'),
    );
    await Future<void>.delayed(const Duration(milliseconds: 30));
    await Future.wait([
      Library.instance.activate(_service),
      HomeConfig.instance.activate(_service),
      WatchStats.instance.activate(_service),
    ]);
    expect(Library.instance.favourites.single.name, 'First movie');
    expect(Library.instance.continueWatching().single.key, 'movie:1');
    expect(HomeConfig.instance.shelves.single.name, 'First shelf');
    expect(WatchStats.instance.total, 30);
  });

  test(
    'viewer selection persists, and removal erases only that viewer',
    () async {
      await Store.setActive(_service);
      final second = await ViewingProfiles.instance.add('Sam');
      await ViewingProfiles.instance.select(second.id);
      await ViewingProfiles.instance.load();
      expect(ViewingProfiles.instance.active.name, 'Sam');
      await Store.writePrivate(
        Store.viewingScopedKey('lib_progress', _service, second.id),
        '{}',
      );
      await ViewingProfiles.instance.select(ViewingProfiles.defaultId);
      await ViewingProfiles.instance.remove(second.id);
      expect(ViewingProfiles.instance.profiles, hasLength(1));
      expect(
        await Store.readPrivate(
          Store.viewingScopedKey('lib_progress', _service, second.id),
        ),
        isNull,
      );
    },
  );

  test('service host edit migrates every viewer’s activity', () async {
    const replacement = XtreamCredentials(
      baseUrl: 'https://moved.example',
      username: 'test',
      password: 'secret',
    );
    await Store.setActive(_service);
    final second = await ViewingProfiles.instance.add('Sam');
    final oldKey = Store.viewingScopedKey('lib_progress', _service, second.id);
    final newKey = Store.viewingScopedKey(
      'lib_progress',
      replacement,
      second.id,
    );
    await Store.writePrivate(oldKey, 'https://one.example/movie/1');

    await Store.updateProfile(_service, replacement);

    expect(await Store.readPrivate(oldKey), isNull);
    expect(await Store.readPrivate(newKey), 'https://moved.example/movie/1');
  });

  testWidgets('viewer picker has keyboard-focusable switching targets', (
    tester,
  ) async {
    final second = await ViewingProfiles.instance.add('Sam');
    String? selected;
    await tester.pumpWidget(
      MaterialApp(
        home: ViewerPickerScreen(onSelect: (id) async => selected = id),
      ),
    );
    await tester.pump();
    expect(find.text('Who’s watching?'), findsOneWidget);
    expect(find.text('Sam'), findsOneWidget);
    Focus.of(tester.element(find.text('Sam'))).requestFocus();
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    expect(selected, second.id);
    expect(tester.takeException(), isNull);
  });
}
