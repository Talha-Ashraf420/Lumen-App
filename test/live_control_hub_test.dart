import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lumen_tv/library.dart';
import 'package:lumen_tv/playback.dart';
import 'package:lumen_tv/screens/live_control_hub.dart';

void main() {
  final controller = PlaybackController.instance;

  tearDown(() {
    controller.items = [];
    controller.index = 0;
    Library.instance.recent.clear();
    Library.instance.favourites.clear();
  });

  testWidgets('live hub stays usable at a narrow phone player width', (
    tester,
  ) async {
    const one = MediaRef(
      kind: 'live',
      id: 11,
      name: 'News One',
      url: 'https://example.test/11.ts',
    );
    const two = MediaRef(
      kind: 'live',
      id: 12,
      name: 'Sports Two',
      url: 'https://example.test/12.ts',
    );
    controller.items = const [
      PlayerItem(
        'https://example.test/11.ts',
        'News One',
        isLive: true,
        favRef: one,
      ),
      PlayerItem(
        'https://example.test/12.ts',
        'Sports Two',
        isLive: true,
        favRef: two,
      ),
    ];
    Library.instance.recent.add(two);

    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData.dark(),
        home: Scaffold(
          body: Align(
            alignment: Alignment.centerRight,
            child: SizedBox(
              width: 330,
              height: 600,
              child: LiveControlHub(
                controller: controller,
                onSelect: (_, _) {},
                onClose: () {},
              ),
            ),
          ),
        ),
      ),
    );

    expect(find.text('Live control hub'), findsOneWidget);
    expect(find.text('News One'), findsOneWidget);
    expect(find.text('Sports Two'), findsOneWidget);
    expect(find.text('Loading programme…'), findsNothing);
    expect(find.text('Live now'), findsNWidgets(2));
    expect(tester.takeException(), isNull);

    await tester.tap(find.text('Recent'));
    await tester.pump();

    expect(find.text('Sports Two'), findsOneWidget);
    expect(find.text('News One'), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
