import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';

/// Monotonic build number, injected by CI (`--dart-define=APP_BUILD=<run>`).
/// 0 in local dev builds (we never prompt to "update" a dev build).
const int kBuildNumber = int.fromEnvironment('APP_BUILD', defaultValue: 0);

class UpdateInfo {
  final int build;
  final String name;
  final String notes;
  final String releaseUrl;
  final String? androidDownloadUrl;
  UpdateInfo({
    required this.build,
    required this.name,
    required this.notes,
    required this.releaseUrl,
    this.androidDownloadUrl,
  });
}

enum AppDistribution { playStore, community, desktop, appStore, other }

enum UpdateCheckStatus { upToDate, available, failed }

class UpdateCheckResult {
  final UpdateCheckStatus status;
  final UpdateInfo? info;
  final String? error;
  const UpdateCheckResult._(this.status, {this.info, this.error});
  const UpdateCheckResult.upToDate() : this._(UpdateCheckStatus.upToDate);
  const UpdateCheckResult.available(UpdateInfo value)
    : this._(UpdateCheckStatus.available, info: value);
  const UpdateCheckResult.failed(String message)
    : this._(UpdateCheckStatus.failed, error: message);
}

/// Keeps version and update routing consistent across every Lumen surface.
///
/// Google Play builds always stay inside Google's update channel. Community
/// Android builds and desktop builds use the signed artifacts attached to the
/// project's latest GitHub release.
class Updater {
  Updater._();
  static final Updater instance = Updater._();

  static const _releaseApi =
      'https://api.github.com/repos/Talha-Ashraf420/Lumen-App/releases/latest';
  static const _playStoreUrl =
      'https://play.google.com/store/apps/details?id=com.talhaashraf.lumen';
  static const _playStoreAppUrl = 'market://details?id=com.talhaashraf.lumen';

  String _version = '';
  int _installedBuild = kBuildNumber;
  String _packageName = '';
  bool _initialized = false;

  Future<void> initialize() async {
    if (_initialized) return;
    try {
      final package = await PackageInfo.fromPlatform();
      _version = package.version.trim();
      _packageName = package.packageName.trim();
      _installedBuild = kBuildNumber > 0
          ? kBuildNumber
          : int.tryParse(package.buildNumber.trim()) ?? 0;
    } catch (_) {
      // Unit tests and unsupported embedders can lack a package-info channel.
      // Keep the compile-time build as a useful, deterministic fallback.
    }
    _initialized = true;
  }

  AppDistribution get distribution {
    if (kIsWeb) return AppDistribution.other;
    if (Platform.isAndroid) {
      return _packageName.endsWith('.community')
          ? AppDistribution.community
          : AppDistribution.playStore;
    }
    if (Platform.isMacOS || Platform.isWindows || Platform.isLinux) {
      return AppDistribution.desktop;
    }
    if (Platform.isIOS) return AppDistribution.appStore;
    return AppDistribution.other;
  }

  String get currentLabel {
    final version = _version.isEmpty ? null : 'v$_version';
    final build = _installedBuild > 0 ? 'Build $_installedBuild' : null;
    return [version, build].whereType<String>().join(' · ').trim().isEmpty
        ? 'Development build'
        : [version, build].whereType<String>().join(' · ');
  }

  String get distributionLabel => switch (distribution) {
    AppDistribution.playStore => 'Google Play',
    AppDistribution.community => 'Community APK',
    AppDistribution.desktop => 'GitHub release',
    AppDistribution.appStore => 'App Store',
    AppDistribution.other => 'Installed package',
  };

  String get updateActionLabel => switch (distribution) {
    AppDistribution.playStore => 'Open Google Play',
    AppDistribution.community => 'Download signed APK',
    AppDistribution.desktop => 'Open release download',
    AppDistribution.appStore => 'Open App Store',
    AppDistribution.other => 'Check for updates',
  };

  bool get isEnabled =>
      !kIsWeb &&
      (Platform.isAndroid ||
          Platform.isMacOS ||
          Platform.isWindows ||
          Platform.isLinux);

  bool get supportsReleaseCheck =>
      distribution == AppDistribution.community ||
      distribution == AppDistribution.desktop;

  /// Distinguishes a successful up-to-date result from API/network failure.
  Future<UpdateCheckResult> check() async {
    await initialize();
    if (!supportsReleaseCheck) {
      return const UpdateCheckResult.failed(
        'This installation is updated by its app store.',
      );
    }
    try {
      final res = await http
          .get(
            Uri.parse(_releaseApi),
            headers: {
              'Accept': 'application/vnd.github+json',
              'User-Agent': 'Lumen',
            },
          )
          .timeout(const Duration(seconds: 15));
      if (res.statusCode != 200) {
        return UpdateCheckResult.failed(
          'Update server returned ${res.statusCode}.',
        );
      }
      final j = jsonDecode(res.body) as Map<String, dynamic>;
      final name = (j['name'] ?? '').toString();
      final body = (j['body'] ?? '').toString();
      final latest = _parseBuild(body) ?? _parseBuild(name);
      if (latest == null) {
        return const UpdateCheckResult.failed(
          'The release has no valid build number.',
        );
      }
      // Local debug builds have no CI build identity and must never encourage
      // developers to replace the running app with a release package.
      if (kDebugMode && kBuildNumber == 0) {
        return const UpdateCheckResult.upToDate();
      }
      if (latest <= _installedBuild) return const UpdateCheckResult.upToDate();

      String? androidDownloadUrl;
      final assets = j['assets'];
      if (assets is List) {
        for (final asset in assets.whereType<Map<String, dynamic>>()) {
          if ((asset['name'] ?? '').toString() == 'Lumen-Android.apk') {
            final candidate = (asset['browser_download_url'] ?? '').toString();
            if (candidate.startsWith('https://')) {
              androidDownloadUrl = candidate;
            }
            break;
          }
        }
      }

      return UpdateCheckResult.available(
        UpdateInfo(
          build: latest,
          name: name.isEmpty ? 'Build $latest' : name,
          notes: body.replaceFirst(RegExp(r'build:\s*\d+\s*'), '').trim(),
          releaseUrl:
              (j['html_url'] ??
                      'https://github.com/Talha-Ashraf420/Lumen-App/releases/latest')
                  .toString(),
          androidDownloadUrl: androidDownloadUrl,
        ),
      );
    } on TimeoutException {
      return const UpdateCheckResult.failed('The update check timed out.');
    } on SocketException {
      return const UpdateCheckResult.failed(
        'Could not reach the update server.',
      );
    } catch (_) {
      return const UpdateCheckResult.failed('The update response was invalid.');
    }
  }

  int? _parseBuild(String s) {
    final m =
        RegExp(r'build:\s*(\d+)', caseSensitive: false).firstMatch(s) ??
        RegExp(r'Build\s+(\d+)').firstMatch(s);
    return m == null ? null : int.tryParse(m.group(1)!);
  }

  Future<bool> openStorePage() async {
    final openedInPlay = await launchUrl(
      Uri.parse(_playStoreAppUrl),
      mode: LaunchMode.externalApplication,
    );
    if (openedInPlay) return true;
    return launchUrl(
      Uri.parse(_playStoreUrl),
      mode: LaunchMode.externalApplication,
    );
  }

  Future<bool> openUpdate(UpdateInfo info) async {
    final destination = distribution == AppDistribution.community
        ? info.androidDownloadUrl ?? info.releaseUrl
        : info.releaseUrl;
    final opened = await launchUrl(
      Uri.parse(destination),
      mode: LaunchMode.externalApplication,
    );
    if (opened || destination == info.releaseUrl) return opened;
    return launchUrl(
      Uri.parse(info.releaseUrl),
      mode: LaunchMode.externalApplication,
    );
  }
}
