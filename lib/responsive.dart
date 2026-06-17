import 'package:flutter/widgets.dart';

/// Layout breakpoint: at/above this width we use the desktop layout (sidebar,
/// multi-column grids, centered content); below it the mobile layout.
const double kWideBreakpoint = 900;

/// Centering cap so content doesn't stretch edge-to-edge on huge monitors.
const double kMaxContent = 1500;

bool isWide(BuildContext context) => MediaQuery.sizeOf(context).width >= kWideBreakpoint;

/// Column count for a grid given the available [width] and a target [tile] size.
int gridColumns(double width, {double tile = 170, int min = 3, int max = 8}) {
  final n = (width / tile).floor();
  return n.clamp(min, max);
}
