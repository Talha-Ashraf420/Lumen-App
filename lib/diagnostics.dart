import 'dart:io' show Platform;
import 'dart:ui' show Rect;

import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:share_plus/share_plus.dart';

import 'device_profile.dart';
import 'models.dart';
import 'network_path.dart';
import 'playback.dart';

/// One short, in-memory application event suitable for a support report.
class LumenDiagnosticEvent {
  const LumenDiagnosticEvent({
    required this.time,
    required this.area,
    required this.message,
  });

  final DateTime time;
  final String area;
  final String message;
}

/// Builds support reports without collecting or uploading user data.
///
/// Events are deliberately bounded and memory-only. Reports exclude provider
/// addresses, credentials, playlist URLs, account names and media history.
class AppDiagnostics {
  AppDiagnostics._();

  static final AppDiagnostics instance = AppDiagnostics._();
  static const int _eventLimit = 40;
  final List<LumenDiagnosticEvent> _events = [];

  List<LumenDiagnosticEvent> get events => List.unmodifiable(_events);

  void record(String area, String message) {
    final safeArea = redactDiagnosticText(area).trim();
    final safeMessage = redactDiagnosticText(message).trim();
    if (safeArea.isEmpty || safeMessage.isEmpty) return;
    _events.insert(
      0,
      LumenDiagnosticEvent(
        time: DateTime.now().toUtc(),
        area: safeArea,
        message: safeMessage,
      ),
    );
    if (_events.length > _eventLimit) {
      _events.removeRange(_eventLimit, _events.length);
    }
  }

  static String sourceLabel(XtreamCredentials credentials) {
    if (credentials.isDemo) return 'Offline demo';
    if (credentials.isM3u) return 'M3U playlist';
    return 'Provider account';
  }

  Future<String> buildReport({
    required XtreamCredentials credentials,
    String userNotes = '',
  }) async {
    final package = await _packageDetails();
    final device = await _deviceDetails();
    final playback = PlaybackController.instance;
    final now = DateTime.now().toUtc();
    final notes = redactDiagnosticText(userNotes).trim();

    final lines = <String>[
      'LUMEN DIAGNOSTIC REPORT',
      'Generated: ${now.toIso8601String()}',
      '',
      'PRIVACY',
      'Nothing was uploaded automatically.',
      'Provider addresses, credentials, playlist URLs, account names, media titles and viewing history are excluded.',
      '',
      'APP',
      'Version: ${package.version}',
      'Build: ${package.buildNumber}',
      'Install source: ${package.installerStore ?? 'Unknown'}',
      '',
      'DEVICE',
      'Class: ${DeviceProfile.isTelevision ? 'Television' : _deviceClass()}',
      'Platform: ${device.platform}',
      'Model: ${device.model}',
      'OS: ${device.operatingSystem}',
      'Physical device: ${device.isPhysicalDevice}',
      'Active network: ${NetworkPathMonitor.instance.current.label}',
      '',
      'LIBRARY',
      'Source type: ${sourceLabel(credentials)}',
    ];

    if (playback.hasMedia || playback.diagnosticEvents.isNotEmpty) {
      lines.addAll([
        '',
        'PLAYBACK',
        'State: ${playback.playbackStateLabel}',
        'Format: ${redactDiagnosticText(playback.sourceFormat)}',
        'Source candidate: ${playback.sourceNumber}/${playback.sourceCount}',
        'Recovery attempt: ${playback.reconnectAttempt}/${playback.retryLimit}',
        'Buffered ahead: ${playback.bufferedAhead.inSeconds}s',
        if (playback.failure != null)
          'Failure code: ${redactDiagnosticText(playback.failure!.code)}',
      ]);
      if (playback.diagnosticEvents.isNotEmpty) {
        lines.add('Recent playback events:');
        for (final event in playback.diagnosticEvents.take(10)) {
          lines.add(
            '- ${_clock(event.time)} ${redactDiagnosticText(event.label)}: '
            '${redactDiagnosticText(event.detail)}',
          );
        }
      }
    }

    lines.addAll(['', 'RECENT APP EVENTS']);
    if (_events.isEmpty) {
      lines.add('- None recorded in this app session.');
    } else {
      for (final event in _events.take(20)) {
        lines.add('- ${_clock(event.time)} ${event.area}: ${event.message}');
      }
    }

    if (notes.isNotEmpty) {
      lines.addAll(['', 'USER NOTES', notes]);
    }

    var report = lines.join('\n');
    for (final secret in [
      credentials.baseUrl,
      credentials.username,
      credentials.password,
      ?credentials.m3uUrl,
    ]) {
      if (secret.trim().length >= 3) {
        report = report.replaceAll(secret, '[redacted]');
      }
    }
    return redactDiagnosticText(report);
  }

  Future<ShareResult> shareReport(String report, {Rect? sharePositionOrigin}) =>
      SharePlus.instance.share(
        ShareParams(
          text: report,
          subject: 'Lumen diagnostic report',
          title: 'Lumen diagnostic report',
          sharePositionOrigin: sharePositionOrigin,
        ),
      );

  @visibleForTesting
  void clearForTesting() => _events.clear();

  static String _clock(DateTime value) =>
      value.toUtc().toIso8601String().substring(11, 19);

  static String _deviceClass() {
    if (kIsWeb) return 'Web browser';
    if (Platform.isAndroid || Platform.isIOS) return 'Phone or tablet';
    return 'Desktop';
  }

  Future<_PackageDetails> _packageDetails() async {
    try {
      final info = await PackageInfo.fromPlatform();
      return _PackageDetails(
        version: info.version.isEmpty ? 'Unknown' : info.version,
        buildNumber: info.buildNumber.isEmpty ? 'Unknown' : info.buildNumber,
        installerStore: info.installerStore,
      );
    } catch (_) {
      return const _PackageDetails(
        version: 'Unknown',
        buildNumber: 'Unknown',
        installerStore: null,
      );
    }
  }

  Future<_DeviceDetails> _deviceDetails() async {
    if (kIsWeb) {
      return const _DeviceDetails(
        platform: 'Web',
        model: 'Browser',
        operatingSystem: 'Browser',
        isPhysicalDevice: 'Unknown',
      );
    }
    try {
      final data = (await DeviceInfoPlugin().deviceInfo).data;
      final model = _firstSafeValue(data, const [
        'model',
        'productName',
        'product',
        'machine',
        'prettyName',
      ]);
      final maker = _firstSafeValue(data, const ['manufacturer', 'brand']);
      return _DeviceDetails(
        platform: Platform.operatingSystem,
        model:
            [
              if (maker != 'Unknown') maker,
              if (model != 'Unknown') model,
            ].join(' ').trim().isEmpty
            ? 'Unknown'
            : [
                if (maker != 'Unknown') maker,
                if (model != 'Unknown') model,
              ].join(' '),
        operatingSystem: redactDiagnosticText(Platform.operatingSystemVersion),
        isPhysicalDevice: _physicalDeviceValue(data),
      );
    } catch (_) {
      return _DeviceDetails(
        platform: Platform.operatingSystem,
        model: 'Unknown',
        operatingSystem: redactDiagnosticText(Platform.operatingSystemVersion),
        isPhysicalDevice: 'Unknown',
      );
    }
  }

  static String _firstSafeValue(Map<String, dynamic> data, List<String> keys) {
    for (final key in keys) {
      final value = data[key];
      if (value is String && value.trim().isNotEmpty) {
        return redactDiagnosticText(value.trim());
      }
    }
    return 'Unknown';
  }

  static String _physicalDeviceValue(Map<String, dynamic> data) {
    final value = data['isPhysicalDevice'];
    return value is bool ? (value ? 'Yes' : 'No') : 'Unknown';
  }
}

class _PackageDetails {
  const _PackageDetails({
    required this.version,
    required this.buildNumber,
    required this.installerStore,
  });

  final String version;
  final String buildNumber;
  final String? installerStore;
}

class _DeviceDetails {
  const _DeviceDetails({
    required this.platform,
    required this.model,
    required this.operatingSystem,
    required this.isPhysicalDevice,
  });

  final String platform;
  final String model;
  final String operatingSystem;
  final String isPhysicalDevice;
}

/// Removes common secrets and endpoints before text reaches a support report.
@visibleForTesting
String redactDiagnosticText(String value) {
  var safe = value;
  safe = safe.replaceAll(
    RegExp(
      r'\b(?:https?|rtsp|rtmp|mms|demo)://[^\s<>()]+',
      caseSensitive: false,
    ),
    '[redacted-url]',
  );
  safe = safe.replaceAll(
    RegExp(
      r'\b(?:https?|rtsp|rtmp|mms)\s*[·:]\s*[^\s,;]+',
      caseSensitive: false,
    ),
    '[redacted-endpoint]',
  );
  safe = safe.replaceAll(
    RegExp(r'\b[\w.+-]+@[\w.-]+\.[a-z]{2,}\b', caseSensitive: false),
    '[redacted-email]',
  );
  safe = safe.replaceAll(
    RegExp(r'\b(?:\d{1,3}\.){3}\d{1,3}(?::\d+)?\b'),
    '[redacted-host]',
  );
  safe = safe.replaceAll(
    RegExp(r'\b(?:[a-z0-9-]+\.)+[a-z]{2,}(?::\d+)?\b', caseSensitive: false),
    '[redacted-host]',
  );
  safe = safe.replaceAllMapped(
    RegExp(
      r'\b(password|passwd|pwd|username|user|token|authorization|auth|api[_-]?key)\s*[:=]\s*[^\s,;]+',
      caseSensitive: false,
    ),
    (match) => '${match.group(1)}=[redacted]',
  );
  return safe.length <= 12000 ? safe : '${safe.substring(0, 12000)}\n[trimmed]';
}
