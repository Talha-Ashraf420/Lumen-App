import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lumen_tv/responsive.dart';
import 'package:lumen_tv/widgets.dart';

void main() {
  for (final width in [320.0, 390.0, 844.0, 1280.0]) {
    testWidgets('page edges align at $width with safe area', (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = Size(width, 900);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPhysicalSize);
      final gutter = width >= 900 ? 32.0 : (width < 360 ? 20.0 : 24.0);
      late EdgeInsets insets;
      late double bottom;
      await tester.pumpWidget(
        MaterialApp(
          home: MediaQuery(
            data: MediaQueryData(
              size: Size(width, 900),
              padding: const EdgeInsets.fromLTRB(12, 44, 12, 34),
            ),
            child: SafeArea(
              bottom: false,
              child: Builder(
                builder: (context) {
                  insets = pageInsets(context);
                  bottom = pageScrollBottom(context);
                  return Column(
                    children: [
                      const EditorialPageHeader(
                        eyebrow: 'Library',
                        title: 'My list',
                        subtitle: 'Saved for later',
                        icon: Icons.favorite,
                      ),
                      Padding(
                        padding: insets,
                        child: Container(
                          key: const ValueKey('content'),
                          height: 40,
                          color: Colors.black,
                        ),
                      ),
                    ],
                  );
                },
              ),
            ),
          ),
        ),
      );
      expect(insets, EdgeInsets.all(gutter).copyWith(top: 24, bottom: 24));
      expect(bottom, width >= 900 ? 32 : 146);
      final content = tester.getRect(find.byKey(const ValueKey('content')));
      expect(content.left, 12 + gutter);
      expect(content.right, width - 12 - gutter);
      final headerPadding = tester.widget<Padding>(
        find
            .descendant(
              of: find.byType(EditorialPageHeader),
              matching: find.byType(Padding),
            )
            .first,
      );
      expect(headerPadding.padding.resolve(TextDirection.ltr).left, gutter);
      expect(tester.takeException(), isNull);
    });
  }
}
