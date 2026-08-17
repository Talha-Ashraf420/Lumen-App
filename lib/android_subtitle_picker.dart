import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

class PickedSubtitle {
  const PickedSubtitle({
    required this.name,
    required this.data,
    required this.mimeType,
  });

  final String name;
  final String data;
  final String mimeType;
}

/// Opens Android's system document picker without adding storage permissions.
/// The selected subtitle is copied through the platform channel so media_kit
/// can use it immediately even when the provider returns a temporary content
/// URI grant.
class AndroidSubtitlePicker {
  AndroidSubtitlePicker._();

  static const _channel = MethodChannel('lumen/subtitles');

  static bool get isAvailable =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  static Future<PickedSubtitle?> pick() async {
    if (!isAvailable) return null;
    try {
      final raw = await _channel.invokeMapMethod<String, dynamic>('pick');
      if (raw == null) return null;
      final data = '${raw['data'] ?? ''}';
      if (data.trim().isEmpty) {
        throw PlatformException(
          code: 'subtitle_empty',
          message: 'The selected subtitle file is empty.',
        );
      }
      return PickedSubtitle(
        name: '${raw['name'] ?? 'External subtitle'}',
        data: data,
        mimeType: '${raw['mimeType'] ?? 'text/plain'}',
      );
    } on MissingPluginException {
      return null;
    }
  }
}
