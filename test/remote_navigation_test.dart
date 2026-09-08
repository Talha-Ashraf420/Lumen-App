import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lumen_tv/downloads.dart';
import 'package:lumen_tv/library.dart';
import 'package:lumen_tv/models.dart';
import 'package:lumen_tv/widgets.dart';
import 'package:lumen_tv/screens/downloads_screen.dart';
import 'package:lumen_tv/screens/mylist_screen.dart';
import 'package:lumen_tv/screens/player_host.dart';
import 'package:lumen_tv/screens/shell.dart';
import 'package:lumen_tv/xtream.dart';

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

  testWidgets('focus visibility scrolls back upward with D-pad Up', (
    tester,
  ) async {
    final controller = ScrollController();
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: RemoteFocusVisibility(
          child: FocusTraversalGroup(
            policy: RemoteFocusTraversalPolicy(),
            child: Scaffold(
              body: SizedBox(
                width: 260,
                height: 220,
                child: SingleChildScrollView(
                  controller: controller,
                  child: Column(
                    children: [
                      for (var index = 0; index < 10; index++)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 12),
                          child: RemoteTap(
                            autofocus: index == 0,
                            semanticLabel: 'Row $index',
                            onTap: () {},
                            child: const SizedBox(width: 220, height: 70),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    for (var i = 0; i < 7; i++) {
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pumpAndSettle();
    }
    final lowerOffset = controller.offset;
    expect(lowerOffset, greaterThan(0));

    for (var i = 0; i < 3; i++) {
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
      await tester.pumpAndSettle();
    }
    expect(controller.offset, lessThan(lowerOffset));
  });

  testWidgets('D-pad reveals and focuses the next lazy horizontal tile', (
    tester,
  ) async {
    final controller = ScrollController();
    await tester.pumpWidget(
      MaterialApp(
        home: FocusTraversalGroup(
          policy: RemoteFocusTraversalPolicy(),
          child: Scaffold(
            body: SizedBox(
              width: 260,
              height: 90,
              child: ListView.separated(
                controller: controller,
                scrollDirection: Axis.horizontal,
                itemCount: 8,
                separatorBuilder: (_, _) => const SizedBox(width: 20),
                itemBuilder: (_, index) => RemoteTap(
                  autofocus: index == 0,
                  semanticLabel: 'Tile $index',
                  onTap: () {},
                  child: const SizedBox(width: 200, height: 70),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pumpAndSettle();
    expect(controller.offset, greaterThan(0));
    expect(FocusManager.instance.primaryFocus?.context, isNotNull);
  });

  testWidgets('D-pad stays in a lazy grid and reveals the next row', (
    tester,
  ) async {
    final controller = ScrollController();
    final outsideFocus = FocusNode(debugLabel: 'Outside grid');
    addTearDown(controller.dispose);
    addTearDown(outsideFocus.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: FocusTraversalGroup(
          policy: RemoteFocusTraversalPolicy(),
          child: Scaffold(
            body: Row(
              children: [
                SizedBox(
                  width: 260,
                  height: 210,
                  child: GridView.builder(
                    controller: controller,
                    gridDelegate:
                        const SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: 2,
                          mainAxisExtent: 90,
                        ),
                    itemCount: 30,
                    itemBuilder: (_, index) => RemoteTap(
                      autofocus: index == 0,
                      semanticLabel: 'Poster $index',
                      onTap: () {},
                      child: const SizedBox(width: 120, height: 80),
                    ),
                  ),
                ),
                RemoteTap(
                  focusNode: outsideFocus,
                  onTap: () {},
                  child: const SizedBox(width: 100, height: 60),
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
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pumpAndSettle();

    expect(controller.offset, greaterThan(0));
    expect(outsideFocus.hasFocus, isFalse);
  });

  testWidgets('Downloads D-pad moves filter to item and back to shell rail', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1280, 720);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    final railFocus = FocusNode(debugLabel: 'Downloads test rail');
    addTearDown(railFocus.dispose);
    Downloads.instance.items
      ..clear()
      ..add(
        DownloadItem(
          id: 'movie:1',
          title: 'Offline film',
          poster: '',
          kind: 'movie',
          remoteUrl: 'https://example.invalid/movie.mp4',
          fileName: 'offline.mp4',
          progressKey: 'movie:1',
          status: DlStatus.paused,
        ),
      );
    addTearDown(Downloads.instance.items.clear);
    final client = XtreamClient(
      const XtreamCredentials(
        baseUrl: 'https://example.invalid',
        username: 'test',
        password: 'test',
      ),
    );
    addTearDown(client.close);

    await tester.pumpWidget(
      MaterialApp(
        home: FocusTraversalGroup(
          policy: RemoteFocusTraversalPolicy(),
          child: Row(
            children: [
              RemoteTap(
                focusNode: railFocus,
                onTap: () {},
                child: const SizedBox(width: 80, height: 80),
              ),
              Expanded(
                child: DownloadsScreen(
                  client: client,
                  shellRailFocusNode: railFocus,
                ),
              ),
            ],
          ),
        ),
      ),
    );
    await tester.pump();

    final allFilter = tester.widget<FocusableActionDetector>(
      find
          .ancestor(
            of: find.text('All 1'),
            matching: find.byType(FocusableActionDetector),
          )
          .first,
    );
    allFilter.focusNode!.requestFocus();
    await tester.pump();
    expect(
      FocusManager.instance.primaryFocus?.debugLabel,
      'Downloads filter 0',
    );

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pump();
    expect(FocusManager.instance.primaryFocus?.debugLabel, 'Download item 0');

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pump();
    expect(FocusManager.instance.primaryFocus?.debugLabel, 'Resume');
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pump();
    expect(FocusManager.instance.primaryFocus?.debugLabel, 'Cancel');
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
    await tester.pump();
    expect(FocusManager.instance.primaryFocus?.debugLabel, 'Resume');

    _itemFocusAgain:
    for (var i = 0; i < 3; i++) {
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
      await tester.pump();
      if (FocusManager.instance.primaryFocus?.debugLabel == 'Download item 0') {
        break _itemFocusAgain;
      }
    }
    expect(FocusManager.instance.primaryFocus?.debugLabel, 'Download item 0');

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
    await tester.pump();
    expect(
      FocusManager.instance.primaryFocus?.debugLabel,
      'Downloads filter 0',
    );

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
    await tester.pump();
    expect(railFocus.hasFocus, isTrue);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 1));
  });

  testWidgets(
    'My List restores visible focus after filtering a scrolled grid',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(1280, 720);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPhysicalSize);
      Library.instance.favourites
        ..clear()
        ..addAll([
          for (var index = 0; index < 60; index++)
            MediaRef(kind: 'movie', id: index, name: 'Film $index'),
          for (var index = 0; index < 60; index++)
            MediaRef(kind: 'series', id: 1000 + index, name: 'Series $index'),
        ]);
      addTearDown(Library.instance.favourites.clear);
      final client = XtreamClient(
        const XtreamCredentials(
          baseUrl: 'https://example.invalid',
          username: 'test',
          password: 'test',
        ),
      );
      addTearDown(client.close);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: MyListScreen(client: client)),
        ),
      );
      await tester.pump();
      final grid = find.byType(GridView);
      await tester.drag(grid, const Offset(0, -2600));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Films 60'));
      await tester.pump();
      await tester.tap(find.text('All 120'));
      await tester.pump();
      final allFilter = tester.widget<FocusableActionDetector>(
        find
            .ancestor(
              of: find.text('All 120'),
              matching: find.byType(FocusableActionDetector),
            )
            .first,
      );
      allFilter.focusNode!.requestFocus();
      await tester.pump();

      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pump();
      await tester.pump();
      expect(FocusManager.instance.primaryFocus?.debugLabel, 'My List tile 0');
      final tileContext = FocusManager.instance.primaryFocus!.context!;
      final tileBox = tileContext.findRenderObject()! as RenderBox;
      final gridBox = tester.renderObject<RenderBox>(grid);
      final tileCenter = tileBox.localToGlobal(
        tileBox.size.center(Offset.zero),
      );
      final gridRect = gridBox.localToGlobal(Offset.zero) & gridBox.size;
      expect(gridRect.contains(tileCenter), isTrue);
      expect(tester.takeException(), isNull);

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(seconds: 1));
    },
  );

  testWidgets(
    'Downloads restores visible focus after filtering a scrolled grid',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(1280, 720);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPhysicalSize);
      Downloads.instance.items
        ..clear()
        ..addAll([
          for (var index = 0; index < 60; index++)
            DownloadItem(
              id: 'ready:$index',
              title: 'Ready $index',
              poster: '',
              kind: 'movie',
              remoteUrl: 'https://example.invalid/ready-$index.mp4',
              fileName: 'ready-$index.mp4',
              progressKey: 'movie:$index',
              status: DlStatus.completed,
            ),
          for (var index = 0; index < 60; index++)
            DownloadItem(
              id: 'active:$index',
              title: 'Active $index',
              poster: '',
              kind: 'movie',
              remoteUrl: 'https://example.invalid/active-$index.mp4',
              fileName: 'active-$index.mp4',
              progressKey: 'movie:${1000 + index}',
              status: DlStatus.paused,
            ),
        ]);
      addTearDown(Downloads.instance.items.clear);
      final client = XtreamClient(
        const XtreamCredentials(
          baseUrl: 'https://example.invalid',
          username: 'test',
          password: 'test',
        ),
      );
      addTearDown(client.close);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: DownloadsScreen(client: client)),
        ),
      );
      await tester.pump();
      final grid = find.byType(GridView);
      await tester.drag(grid, const Offset(0, -2600));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Ready 60'));
      await tester.pump();
      await tester.tap(find.text('All 120'));
      await tester.pump();
      final allFilter = tester.widget<FocusableActionDetector>(
        find
            .ancestor(
              of: find.text('All 120'),
              matching: find.byType(FocusableActionDetector),
            )
            .first,
      );
      allFilter.focusNode!.requestFocus();
      await tester.pump();

      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pump();
      await tester.pump();
      expect(FocusManager.instance.primaryFocus?.debugLabel, 'Download item 0');
      final itemContext = FocusManager.instance.primaryFocus!.context!;
      final itemBox = itemContext.findRenderObject()! as RenderBox;
      final gridBox = tester.renderObject<RenderBox>(grid);
      final itemCenter = itemBox.localToGlobal(
        itemBox.size.center(Offset.zero),
      );
      final gridRect = gridBox.localToGlobal(Offset.zero) & gridBox.size;
      expect(gridRect.contains(itemCenter), isTrue);
      expect(tester.takeException(), isNull);

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(seconds: 1));
    },
  );

  testWidgets('navigation tabs can select as soon as focus lands', (
    tester,
  ) async {
    final firstFocus = FocusNode();
    final secondFocus = FocusNode();
    var selected = 0;
    addTearDown(firstFocus.dispose);
    addTearDown(secondFocus.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Row(
            children: [
              RemoteTap(
                focusNode: firstFocus,
                autofocus: true,
                onTap: () => selected = 0,
                child: const SizedBox(width: 100, height: 60),
              ),
              RemoteTap(
                focusNode: secondFocus,
                onFocusChange: (focused) {
                  if (focused) selected = 1;
                },
                onTap: () => selected = 1,
                child: const SizedBox(width: 100, height: 60),
              ),
            ],
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pump();

    expect(secondFocus.hasFocus, isTrue);
    expect(selected, 1);
  });

  testWidgets('catalog tile key routing cannot lose focus after tile two', (
    tester,
  ) async {
    final nodes = List.generate(3, (i) => FocusNode(debugLabel: 'Tile $i'));
    final outside = FocusNode(debugLabel: 'Outside');
    for (final node in [...nodes, outside]) {
      addTearDown(node.dispose);
    }
    KeyEventResult route(int index, KeyEvent event) {
      if (event is! KeyDownEvent) return KeyEventResult.ignored;
      if (event.logicalKey != LogicalKeyboardKey.arrowRight) {
        return KeyEventResult.ignored;
      }
      if (index + 1 >= nodes.length) return KeyEventResult.handled;
      nodes[index + 1].requestFocus();
      return KeyEventResult.handled;
    }

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Row(
            children: [
              for (var i = 0; i < nodes.length; i++)
                FocusableTap(
                  focusNode: nodes[i],
                  autofocus: i == 0,
                  onKeyEvent: (_, event) => route(i, event),
                  onTap: () {},
                  builder: (_, _) => const SizedBox(width: 80, height: 60),
                ),
              RemoteTap(
                focusNode: outside,
                onTap: () {},
                child: const SizedBox(width: 80, height: 60),
              ),
            ],
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pump();
    expect(nodes[1].hasFocus, isTrue);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pump();
    expect(nodes[2].hasFocus, isTrue);
    expect(outside.hasFocus, isFalse);
  });

  testWidgets('Up and Down escape a TV text field', (tester) async {
    final fieldFocus = FocusNode();
    final buttonFocus = FocusNode();
    addTearDown(fieldFocus.dispose);
    addTearDown(buttonFocus.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Column(
            children: [
              RemoteTextInput(child: TextField(focusNode: fieldFocus)),
              RemoteTap(
                focusNode: buttonFocus,
                onTap: () {},
                child: const SizedBox(width: 100, height: 50),
              ),
            ],
          ),
        ),
      ),
    );
    fieldFocus.requestFocus();
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pump();
    expect(buttonFocus.hasFocus, isTrue);
  });

  testWidgets('excluded pages cannot capture remote focus', (tester) async {
    final visibleFocus = FocusNode();
    final hiddenFocus = FocusNode();
    addTearDown(visibleFocus.dispose);
    addTearDown(hiddenFocus.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: Row(
          children: [
            RemoteTap(
              focusNode: visibleFocus,
              autofocus: true,
              onTap: () {},
              child: const SizedBox(width: 100, height: 50),
            ),
            ExcludeFocus(
              child: RemoteTap(
                focusNode: hiddenFocus,
                onTap: () {},
                child: const SizedBox(width: 100, height: 50),
              ),
            ),
          ],
        ),
      ),
    );
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pump();
    expect(visibleFocus.hasFocus, isTrue);
    expect(hiddenFocus.hasFocus, isFalse);
  });

  testWidgets('standard Material controls scroll into view when focused', (
    tester,
  ) async {
    final controller = ScrollController();
    final buttonFocus = FocusNode();
    addTearDown(controller.dispose);
    addTearDown(buttonFocus.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: RemoteFocusVisibility(
          child: Scaffold(
            body: SingleChildScrollView(
              controller: controller,
              child: Column(
                children: [
                  const SizedBox(height: 900),
                  FilledButton(
                    focusNode: buttonFocus,
                    onPressed: () {},
                    child: const Text('Standard action'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    buttonFocus.requestFocus();
    await tester.pumpAndSettle();
    expect(controller.offset, greaterThan(0));
  });

  testWidgets('Home exit confirmation defaults safely to No', (tester) async {
    expect(homeBackActionFor(0), HomeBackAction.confirmExit);
    expect(homeBackActionFor(4), HomeBackAction.navigateBack);
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () => showHomeExitConfirmation(context),
            child: const Text('Open'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    expect(find.text('Exit Lumen?'), findsOneWidget);
    final noButton = tester.widget<TextButton>(
      find.widgetWithText(TextButton, 'No'),
    );
    expect(noButton.autofocus, isTrue);
  });

  test('player Back returns to the app unless a panel is open', () {
    expect(playerBackActionFor(panelOpen: false), PlayerBackAction.minimize);
    expect(playerBackActionFor(panelOpen: true), PlayerBackAction.closePanel);
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
