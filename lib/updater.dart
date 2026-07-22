import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher.dart';

/// Monotonic build number, injected by CI (`--dart-define=APP_BUILD=<run>`).
/// 0 in local dev builds (we never prompt to "update" a dev build).
const int kBuildNumber = int.fromEnvironment('APP_BUILD', defaultValue: 0);

class UpdateInfo {
  final int build;
  final String name;
  final String notes;
  final String releaseUrl;
  UpdateInfo({
    required this.build,
    required this.name,
    required this.notes,
    required this.releaseUrl,
  });
}

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

/// Desktop-only update notice against the project's GitHub release. Store
/// builds must be updated exclusively through their platform store.
class Updater {
  Updater._();
  static final Updater instance = Updater._();

  static const _releaseApi =
      'https://api.github.com/repos/Talha-Ashraf420/Lumen-App/releases/latest';

  String get currentLabel =>
      kBuildNumber == 0 ? 'dev build' : 'Build $kBuildNumber';

  bool get isEnabled =>
      !kIsWeb && (Platform.isMacOS || Platform.isWindows || Platform.isLinux);

  /// Distinguishes a successful up-to-date result from API/network failure.
  Future<UpdateCheckResult> check() async {
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
      if (latest <= kBuildNumber) return const UpdateCheckResult.upToDate();

      return UpdateCheckResult.available(
        UpdateInfo(
          build: latest,
          name: name.isEmpty ? 'Build $latest' : name,
          notes: body.replaceFirst(RegExp(r'build:\s*\d+\s*'), '').trim(),
          releaseUrl:
              (j['html_url'] ??
                      'https://github.com/Talha-Ashraf420/Lumen-App/releases/latest')
                  .toString(),
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

  Future<void> openReleasePage(UpdateInfo info) => launchUrl(
    Uri.parse(info.releaseUrl),
    mode: LaunchMode.externalApplication,
  );
}
