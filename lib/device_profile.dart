import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Runtime device characteristics that materially change Lumen's workload.
///
/// Screen width alone is not enough to identify a television: desktop windows,
/// tablets and TVs can all be wide. Android reports its UI mode and hardware
/// features through the native bridge instead.
class DeviceProfile {
  DeviceProfile._();

  static const _channel = MethodChannel('lumen/device');

  static bool isTelevision = false;

  static Future<void> detect() async {
    if (kIsWeb || !Platform.isAndroid) {
      isTelevision = false;
      return;
    }
    try {
      isTelevision =
          await _channel
              .invokeMethod<bool>('isTelevision')
              .timeout(const Duration(milliseconds: 800)) ??
          false;
    } catch (_) {
      // Feature detection is an optimization, never a startup requirement.
      isTelevision = false;
    }
  }
}
