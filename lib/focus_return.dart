import 'package:flutter/material.dart';

/// Remembers the control that launched a temporary route or full-screen
/// player, then safely returns focus when that surface closes.
class FocusReturnTarget {
  FocusNode? _target;

  void capture() {
    final node = FocusManager.instance.primaryFocus;
    final nodeContext = node?.context;
    if (node != null && nodeContext != null && nodeContext.mounted) {
      _target = node;
    }
  }

  void clear() => _target = null;

  void restore({bool clearAfterRestore = true}) {
    final node = _target;
    if (clearAfterRestore) _target = null;
    if (node == null) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final nodeContext = node.context;
      if (nodeContext == null ||
          !nodeContext.mounted ||
          !node.canRequestFocus) {
        return;
      }
      node.requestFocus();
      Scrollable.ensureVisible(
        nodeContext,
        alignmentPolicy: ScrollPositionAlignmentPolicy.keepVisibleAtEnd,
        duration: const Duration(milliseconds: 140),
        curve: Curves.easeOutCubic,
      );
    });
    WidgetsBinding.instance.ensureVisualUpdate();
  }
}

/// Pushes a detail surface while preserving its exact launching control.
Future<T?> pushWithFocusReturn<T>(
  BuildContext context,
  Widget destination,
) async {
  final focus = FocusReturnTarget()..capture();
  final result = await Navigator.of(
    context,
  ).push<T>(MaterialPageRoute(builder: (_) => destination));
  focus.restore();
  return result;
}
