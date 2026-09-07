import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lumen_tv/device_profile.dart';
import 'package:lumen_tv/responsive.dart';

void main() {
  test('4K television surfaces normalize to a 1280x720 canvas', () {
    expect(
      televisionViewportScale(
        television: true,
        logicalSize: const Size(960, 540),
        devicePixelRatio: 4,
        panelSize: const Size(3840, 2160),
      ),
      closeTo(0.75, .001),
    );
    expect(
      televisionViewportScale(
        television: true,
        logicalSize: const Size(1280, 720),
        devicePixelRatio: 3,
        panelSize: const Size(3840, 2160),
      ),
      1,
    );
    expect(
      televisionViewportScale(
        television: true,
        logicalSize: const Size(1920, 1080),
        devicePixelRatio: 2,
        panelSize: const Size(3840, 2160),
      ),
      1.5,
    );
    expect(
      televisionViewportScale(
        television: true,
        logicalSize: const Size(1920, 1080),
        devicePixelRatio: 2,
        // Mirrors TVs/emulators whose supportedModes API under-reports the
        // panel even though the active Flutter render surface is 4K.
        panelSize: const Size(1920, 1080),
      ),
      1.5,
    );
    expect(
      televisionViewportScale(
        television: true,
        logicalSize: const Size(3840, 2160),
        devicePixelRatio: 1,
        panelSize: const Size(3840, 2160),
      ),
      3,
    );
    expect(
      televisionViewportScale(
        television: true,
        logicalSize: const Size(960, 540),
        devicePixelRatio: 2,
        panelSize: const Size(1920, 1080),
      ),
      1,
    );
    expect(
      televisionViewportScale(
        television: false,
        logicalSize: const Size(960, 540),
        devicePixelRatio: 4,
        panelSize: const Size(3840, 2160),
      ),
      1,
    );
  });

  test('TV catalog sizing keeps six to eight readable tiles per row', () {
    expect(gridColumns(900, tile: 150), 6);
    expect(gridColumns(1050, tile: 150), 7);
    expect(gridColumns(1280, tile: 150), 8);
  });

  testWidgets('4K television receives a comfortable 1280x720 virtual layout', (
    tester,
  ) async {
    DeviceProfile.isTelevision = true;
    DeviceProfile.televisionPanelSize = const Size(3840, 2160);
    addTearDown(() {
      DeviceProfile.isTelevision = false;
      DeviceProfile.televisionPanelSize = null;
    });
    tester.view.physicalSize = const Size(3840, 2160);
    tester.view.devicePixelRatio = 4;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    Size? observedSize;
    await tester.pumpWidget(
      MaterialApp(
        builder: (context, child) => TelevisionDensityViewport(child: child!),
        home: Builder(
          builder: (context) {
            observedSize = MediaQuery.sizeOf(context);
            return const SizedBox.expand();
          },
        ),
      ),
    );

    expect(observedSize, const Size(1280, 720));
  });

  testWidgets(
    'high-resolution logical TV surfaces are enlarged, not bypassed',
    (tester) async {
      DeviceProfile.isTelevision = true;
      DeviceProfile.televisionPanelSize = const Size(3840, 2160);
      addTearDown(() {
        DeviceProfile.isTelevision = false;
        DeviceProfile.televisionPanelSize = null;
      });
      tester.view.physicalSize = const Size(3840, 2160);
      tester.view.devicePixelRatio = 2;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      Size? observedSize;
      await tester.pumpWidget(
        MaterialApp(
          builder: (context, child) => TelevisionDensityViewport(child: child!),
          home: Builder(
            builder: (context) {
              observedSize = MediaQuery.sizeOf(context);
              return const SizedBox.expand();
            },
          ),
        ),
      );

      expect(observedSize, const Size(1280, 720));
    },
  );
}
