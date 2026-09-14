import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'library.dart';
import 'playback_mode.dart';
import 'theme.dart';

class AndroidCompatibilityPlaylistItem {
  const AndroidCompatibilityPlaylistItem({
    required this.url,
    required this.title,
    this.alternateUrl,
    this.favoriteRef,
    this.progressKey,
    this.poster = '',
    this.ext = '',
    this.resumePositionSeconds = 0,
  });

  final String url;
  final String title;
  final String? alternateUrl;
  final MediaRef? favoriteRef;
  final String? progressKey;
  final String poster;
  final String ext;
  final int resumePositionSeconds;
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
    final initialRef = source[selected].favoriteRef;
    if (initialRef != null) Library.instance.addRecent(initialRef);

    // Intent extras have a strict Binder size limit. Keep a generous window
    // around the selected channel/episode so TV zapping works without risking
    // TransactionTooLargeException on providers with thousands of channels.
    const radius = 100;
    final start = (selected - radius).clamp(0, source.length).toInt();
    final end = (selected + radius + 1).clamp(start, source.length).toInt();
    final window = source.sublist(start, end);
    try {
      final result = await _channel.invokeMethod<Object?>('open', {
        'url': url,
        'title': title,
        'isLive': isLive,
        'playbackMode': PlaybackModeController.instance.mode.value.name,
        'accentColor': ThemeController.instance.accent.value.toARGB32(),
        'headers': headers,
        'playlist': [
          for (final item in window)
            <String, Object?>{
              'url': item.url,
              'title': item.title,
              if (item.alternateUrl?.isNotEmpty ?? false)
                'alternateUrl': item.alternateUrl,
              if (item.favoriteRef case final ref?) ...{
                'favoriteKey': ref.key,
                'favorite': Library.instance.isFav(ref.key),
              },
              'progressKey': item.progressKey,
              if (item.poster.isNotEmpty) 'poster': item.poster,
              if (item.ext.isNotEmpty) 'ext': item.ext,
              if (item.resumePositionSeconds > 0)
                'resumePositionMs': item.resumePositionSeconds * 1000,
            },
        ],
        'initialIndex': selected - start,
      });
      if (result is bool) return result;
      if (result is Map) {
        final keys = (result['favoriteKeys'] as List?)?.cast<Object?>() ?? [];
        final states =
            (result['favoriteStates'] as List?)?.cast<Object?>() ?? [];
        final refs = <String, MediaRef>{};
        for (final item in window) {
          final ref = item.favoriteRef;
          if (ref != null) refs[ref.key] = ref;
        }
        for (
          var index = 0;
          index < keys.length && index < states.length;
          index++
        ) {
          final ref = refs['${keys[index]}'];
          final saved = states[index];
          if (ref != null && saved is bool) {
            Library.instance.setFavorite(ref, saved);
          }
        }
        final lastIndex = result['lastIndex'];
        if (lastIndex is num && lastIndex >= 0 && lastIndex < window.length) {
          final lastRef = window[lastIndex.toInt()].favoriteRef;
          if (lastRef != null) Library.instance.addRecent(lastRef);
        }
        final touched =
            (result['progressTouched'] as List?)?.cast<Object?>() ?? [];
        final positions =
            (result['progressPositionsMs'] as List?)?.cast<Object?>() ?? [];
        final durations =
            (result['progressDurationsMs'] as List?)?.cast<Object?>() ?? [];
        for (var index = 0; index < window.length; index++) {
          if (index >= touched.length || touched[index] != true) continue;
          final item = window[index];
          final key = item.progressKey;
          final position = index < positions.length ? positions[index] : null;
          final duration = index < durations.length ? durations[index] : null;
          if (key == null || position is! num || duration is! num) continue;
          if (duration <= 0) continue;
          Library.instance.saveProgress(
            Progress(
              key: key,
              title: item.title,
              poster: item.poster,
              url: item.url,
              ext: item.ext,
              position: position.toInt() ~/ 1000,
              duration: duration.toInt() ~/ 1000,
              updatedAt: DateTime.now().millisecondsSinceEpoch,
            ),
          );
        }
        return result['opened'] == true;
      }
      return false;
    } on PlatformException {
      return false;
    } on MissingPluginException {
      return false;
    }
  }
}
