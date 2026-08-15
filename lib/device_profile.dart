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
  static const _forceTelevisionForTesting = bool.fromEnvironment(
    'LUMEN_FORCE_TV',
  );

  static bool isTelevision = false;

  static Future<void> detect() async {
    // Lets local/emulator builds exercise the real TV paths without changing
    // production detection. The flag is absent from shipping builds.
    if (_forceTelevisionForTesting) {
      isTelevision = true;
      return;
    }
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
