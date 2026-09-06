import 'dart:math' as math;

import 'package:flutter/widgets.dart';

import 'device_profile.dart';

/// Layout breakpoint: at/above this width we use the desktop layout (sidebar,
/// multi-column grids, centered content); below it the mobile layout.
const double kWideBreakpoint = 900;

/// Centering cap so content doesn't stretch edge-to-edge on huge monitors.
const double kMaxContent = 1500;

bool isWide(BuildContext context) =>
    MediaQuery.sizeOf(context).width >= kWideBreakpoint;

/// Column count for a grid given the available [width] and a target [tile] size.
int gridColumns(double width, {double tile = 170, int min = 3, int max = 8}) {
  final n = (width / tile).floor();
  return n.clamp(min, max);
}

/// Returns the paint scale needed to give a 4K television a stable 1080p
/// design canvas. Some Android TV firmwares report only 960x540 logical pixels
/// for a 3840x2160 panel, making every fixed-size control occupy twice the
/// intended fraction of the screen.
double televisionViewportScale({
  required bool television,
  required Size logicalSize,
  required double devicePixelRatio,
  Size? panelSize,
}) {
  if (!television || logicalSize.width <= logicalSize.height) return 1;
  final surfaceSize = Size(
    logicalSize.width * devicePixelRatio,
    logicalSize.height * devicePixelRatio,
  );
  final nativeSize = panelSize ?? surfaceSize;
  final nativeLongEdge = math.max(nativeSize.width, nativeSize.height);
  if (nativeLongEdge < 3000) return 1;

  const designSize = Size(1920, 1080);
  final scale = math.min(
    logicalSize.width / designSize.width,
    logicalSize.height / designSize.height,
  );
  // Never enlarge an already-correct 1080p logical canvas, and retain a
  // readable minimum if a vendor exposes an unusually tiny render surface.
  return scale.clamp(.5, 1.0);
}

EdgeInsets _divideInsets(EdgeInsets value, double divisor) =>
    EdgeInsets.fromLTRB(
      value.left / divisor,
      value.top / divisor,
      value.right / divisor,
      value.bottom / divisor,
    );

/// Gives 4K Android televisions a denser, consistent app viewport while still
/// painting edge-to-edge at the panel's native output size.
class TelevisionDensityViewport extends StatelessWidget {
  const TelevisionDensityViewport({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final scale = televisionViewportScale(
      television: DeviceProfile.isTelevision,
      logicalSize: media.size,
      devicePixelRatio: media.devicePixelRatio,
      panelSize: DeviceProfile.televisionPanelSize,
    );
    if (scale >= .999) return child;
    final textScale = media.textScaler.scale(1).clamp(0.8, 1.1);

    final virtualSize = Size(
      media.size.width / scale,
      media.size.height / scale,
    );
    final virtualMedia = media.copyWith(
      size: virtualSize,
      // The child is painted smaller by [scale], so this is the effective
      // pixel ratio for image cache/decode sizing inside the virtual canvas.
      devicePixelRatio: media.devicePixelRatio * scale,
      padding: _divideInsets(media.padding, scale),
      viewPadding: _divideInsets(media.viewPadding, scale),
      viewInsets: _divideInsets(media.viewInsets, scale),
      systemGestureInsets: _divideInsets(media.systemGestureInsets, scale),
      textScaler: TextScaler.linear(textScale),
    );

    return ClipRect(
      child: FittedBox(
        fit: BoxFit.fill,
        alignment: Alignment.topLeft,
        child: SizedBox.fromSize(
          size: virtualSize,
          child: MediaQuery(data: virtualMedia, child: child),
        ),
      ),
    );
  }
}
