import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Bridge to Lumen's native Media3 compatibility player.
///
/// It is intentionally an explicit fallback: the regular player retains
/// Lumen's rich cross-platform controls, while Android/TV users can hand a
/// difficult stream to the platform decoder without changing accounts or
/// copying the URL into another app.
class AndroidCompatibilityPlayer {
  AndroidCompatibilityPlayer._();

  static const _channel = MethodChannel('lumen/media3');

  static bool get isAvailable => !kIsWeb && Platform.isAndroid;

  static Future<bool> open({
    required String url,
    required String title,
    required bool isLive,
    required Map<String, String> headers,
  }) async {
    if (!isAvailable) return false;
    try {
      return await _channel.invokeMethod<bool>('open', {
            'url': url,
            'title': title,
            'isLive': isLive,
            'headers': headers,
          }) ??
          false;
    } on PlatformException {
      return false;
    } on MissingPluginException {
      return false;
    }
  }
}
