import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lumen_tv/widgets.dart';

void main() {
  testWidgets('D-pad traverses RemoteTap controls and center activates', (
    tester,
  ) async {
    var firstActivations = 0;
    var secondActivations = 0;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Row(
            children: [
              RemoteTap(
                autofocus: true,
                semanticLabel: 'First',
                onTap: () => firstActivations++,
                child: const SizedBox(width: 120, height: 60),
              ),
              const SizedBox(width: 24),
              RemoteTap(
                semanticLabel: 'Second',
                onTap: () => secondActivations++,
                child: const SizedBox(width: 120, height: 60),
              ),
            ],
          ),
        ),
      ),
    );
    await tester.pump();

    await tester.sendKeyEvent(LogicalKeyboardKey.select);
    await tester.pump();
    expect(firstActivations, 1);

    final remote = tester.widget<FocusableActionDetector>(
      find.byType(FocusableActionDetector).first,
    );
    expect(
      remote.shortcuts!.keys,
      contains(const SingleActivator(LogicalKeyboardKey.accept)),
    );
    expect(
      remote.shortcuts!.keys,
      contains(const SingleActivator(LogicalKeyboardKey.execute)),
    );

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.select);
    await tester.pump();
    expect(secondActivations, 1);
  });

  testWidgets('focused remote control scrolls into view', (tester) async {
    final controller = ScrollController();

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            controller: controller,
            child: Column(
              children: [
                RemoteTap(
                  autofocus: true,
                  onTap: () {},
                  child: const SizedBox(width: 200, height: 80),
                ),
                const SizedBox(height: 900),
                RemoteTap(
                  onTap: () {},
                  child: const SizedBox(width: 200, height: 80),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pumpAndSettle();
    expect(controller.offset, greaterThan(0));
  });

  testWidgets('the single search field accepts programmatic focus', (
    tester,
  ) async {
    final focusNode = FocusNode();
    var query = '';

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SearchField(
            hint: 'Search library',
            focusNode: focusNode,
            onChanged: (value) => query = value,
          ),
        ),
      ),
    );

    focusNode.requestFocus();
    await tester.pump();
    expect(focusNode.hasFocus, isTrue);
    await tester.enterText(find.byType(TextField), 'Furious');
    expect(query, 'Furious');

    await tester.pumpWidget(const SizedBox.shrink());
    focusNode.dispose();
  });
}
