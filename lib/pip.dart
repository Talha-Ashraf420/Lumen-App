import 'dart:io' show Platform;
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Android Picture-in-Picture bridge.
///
/// No-op on every other platform: iOS can't place a libmpv texture in a system
/// PiP window (that needs AVKit/AVPlayer), and desktop has no background-PiP
/// mode. So [active] only ever flips on Android.
class Pip {
  Pip._();
  static final Pip instance = Pip._();

  static const _ch = MethodChannel('lumen/pip');

  /// True while the OS is showing the app in a PiP window.
  final ValueNotifier<bool> active = ValueNotifier<bool>(false);

  bool _wired = false;
  bool get _android => !kIsWeb && Platform.isAndroid;

  void init() {
    if (!_android || _wired) return;
    _wired = true;
    _ch.setMethodCallHandler((call) async {
      if (call.method == 'pipChanged') active.value = call.arguments == true;
      return null;
    });
  }

  /// Tell the OS whether entering PiP is appropriate right now (i.e. a video is
  /// loaded). When true, pressing Home/Recents auto-enters PiP.
  Future<void> setAllowed(bool allowed) async {
    if (!_android) return;
    try {
      await _ch.invokeMethod('setPipAllowed', allowed);
    } catch (_) {}
  }

  /// Enter PiP immediately (e.g. a dedicated button).
  Future<void> enter() async {
    if (!_android) return;
    try {
      await _ch.invokeMethod('enterPip');
    } catch (_) {}
  }
}
