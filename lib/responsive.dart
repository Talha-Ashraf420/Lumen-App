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

/// Returns the paint scale needed to give every 4K television a comfortable
/// 1280x720 ten-foot design canvas.
///
/// Android TV vendors expose wildly different logical surfaces for the same
/// physical 4K panel (commonly 960, 1280, 1920 or even 3840 pixels wide). A
/// fixed Flutter dp value therefore looked four times smaller on some sets.
/// Normalising the *logical* canvas makes typography, focus rings and artwork
/// occupy the same physical proportion on every 4K television.
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
  // Some Android TV firmwares expose only a 1080p entry in supportedModes
  // while the application surface is already 4K; others do the inverse and
  // render apps at 1080p while reporting their 4K panel mode. Trust whichever
  // signal proves the screen is larger so neither vendor behaviour can bypass
  // the ten-foot scale correction.
  final surfaceLongEdge = math.max(surfaceSize.width, surfaceSize.height);
  final panelLongEdge = panelSize == null
      ? 0.0
      : math.max(panelSize.width, panelSize.height);
  final nativeLongEdge = math.max(surfaceLongEdge, panelLongEdge);
  if (nativeLongEdge < 3000) return 1;

  const designSize = Size(1280, 720);
  final scale = math.min(
    logicalSize.width / designSize.width,
    logicalSize.height / designSize.height,
  );
  // A 960-wide Android TV surface still benefits from undoing the old compact
  // scale, while a density-1 4K surface needs the complete 3x correction.
  return scale.clamp(.75, 3.0);
}

EdgeInsets _divideInsets(EdgeInsets value, double divisor) =>
    EdgeInsets.fromLTRB(
      value.left / divisor,
      value.top / divisor,
      value.right / divisor,
      value.bottom / divisor,
    );

/// Gives 4K Android televisions a readable, consistent app viewport while
/// still painting edge-to-edge at the panel's native output size.
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
    // A scale below 1 expands a compact vendor viewport; a scale above 1
    // enlarges the app on high-resolution logical surfaces. Only bypass the
    // transform when the television already exposes the 1280x720 canvas.
    if ((scale - 1).abs() < .001) return child;
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
