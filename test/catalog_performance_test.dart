import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lumen_tv/theme.dart';
import 'package:lumen_tv/widgets.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    activePalette = darkPalette;
  });

  testWidgets('catalog cards bound image decoding and avoid per-tile blur', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 3;
    tester.view.physicalSize = const Size(1170, 2532);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);

    await tester.pumpWidget(
      MaterialApp(
        theme: buildTheme(darkPalette),
        home: Scaffold(
          body: Row(
            children: [
              SizedBox(
                width: 140,
                child: PosterCard(
                  name: 'Bounded poster',
                  image: 'https://images.example/poster.jpg',
                  rating: 8.4,
                  index: 20,
                  onTap: () {},
                ),
              ),
              const SizedBox(width: 16),
              SizedBox(
                width: 140,
                child: ChannelCard(
                  name: 'Bounded channel',
                  logo: 'https://images.example/logo.png',
                  index: 20,
                  onTap: () {},
                ),
              ),
            ],
          ),
        ),
      ),
    );
    await tester.pump();

    final images = tester.widgetList<MediaImage>(find.byType(MediaImage));
    expect(images, hasLength(2));
    expect(images.every((image) => image.memCacheWidth != null), isTrue);
    expect(
      images.every((image) => image.memCacheWidth! <= 640),
      isTrue,
      reason: 'small catalog art must never decode at provider resolution',
    );
    expect(
      find.byType(BackdropFilter),
      findsNothing,
      reason: 'a grid must not create one GPU blur pass per rating badge',
    );
    expect(tester.takeException(), isNull);
  });
}
