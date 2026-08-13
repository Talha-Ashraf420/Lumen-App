import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

class AndroidCompatibilityPlaylistItem {
  const AndroidCompatibilityPlaylistItem({
    required this.url,
    required this.title,
  });

  final String url;
  final String title;
}

/// Bridge to Lumen's native Media3 compatibility player.
///
/// Android TV uses this as its primary playback path because a native
/// SurfaceView is reliable across TV compositors. Phones retain Lumen's rich
/// embedded controls and may use this bridge as a difficult-stream fallback.
class AndroidCompatibilityPlayer {
  AndroidCompatibilityPlayer._();

  static const _channel = MethodChannel('lumen/media3');

  static bool get isAvailable => !kIsWeb && Platform.isAndroid;

  static Future<bool> open({
    required String url,
    required String title,
    required bool isLive,
    required Map<String, String> headers,
    List<AndroidCompatibilityPlaylistItem> playlist = const [],
    int initialIndex = 0,
  }) async {
    if (!isAvailable) return false;
    final source = playlist.isEmpty
        ? <AndroidCompatibilityPlaylistItem>[
            AndroidCompatibilityPlaylistItem(url: url, title: title),
          ]
        : playlist;
    final selected = initialIndex.clamp(0, source.length - 1).toInt();

    // Intent extras have a strict Binder size limit. Keep a generous window
    // around the selected channel/episode so TV zapping works without risking
    // TransactionTooLargeException on providers with thousands of channels.
    const radius = 100;
    final start = (selected - radius).clamp(0, source.length).toInt();
    final end = (selected + radius + 1).clamp(start, source.length).toInt();
    final window = source.sublist(start, end);
    try {
      return await _channel.invokeMethod<bool>('open', {
            'url': url,
            'title': title,
            'isLive': isLive,
            'headers': headers,
            'playlist': [
              for (final item in window)
                <String, String>{'url': item.url, 'title': item.title},
            ],
            'initialIndex': selected - start,
          }) ??
          false;
    } on PlatformException {
      return false;
    } on MissingPluginException {
      return false;
    }
  }
}
