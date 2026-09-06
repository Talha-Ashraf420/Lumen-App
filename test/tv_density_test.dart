import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lumen_tv/device_profile.dart';
import 'package:lumen_tv/responsive.dart';

void main() {
  test('only undersized logical canvases on 4K televisions are compacted', () {
    expect(
      televisionViewportScale(
        television: true,
        logicalSize: const Size(960, 540),
        devicePixelRatio: 4,
        panelSize: const Size(3840, 2160),
      ),
      .5,
    );
    expect(
      televisionViewportScale(
        television: true,
        logicalSize: const Size(1280, 720),
        devicePixelRatio: 3,
        panelSize: const Size(3840, 2160),
      ),
      closeTo(2 / 3, .001),
    );
    expect(
      televisionViewportScale(
        television: true,
        logicalSize: const Size(1920, 1080),
        devicePixelRatio: 2,
        panelSize: const Size(3840, 2160),
      ),
      1,
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

  testWidgets('4K television receives a 1920x1080 virtual layout', (
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

    expect(observedSize, const Size(1920, 1080));
  });
}
