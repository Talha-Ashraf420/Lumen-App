import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:open_filex/open_filex.dart';
import 'package:path_provider/path_provider.dart';
import 'package:url_launcher/url_launcher.dart';

/// Monotonic build number, injected by CI (`--dart-define=APP_BUILD=<run>`).
/// 0 in local dev builds (we never prompt to "update" a dev build).
const int kBuildNumber = int.fromEnvironment('APP_BUILD', defaultValue: 0);

class UpdateInfo {
  final int build;
  final String name;
  final String notes;
  final String? apkUrl; // Android in-app install
  final int? apkSize;
  final String? apkSha256;
  final String? checksumUrl;
  final String releaseUrl; // fallback (desktop / iOS)
  UpdateInfo({
    required this.build,
    required this.name,
    required this.notes,
    required this.apkUrl,
    required this.releaseUrl,
    this.apkSize,
    this.apkSha256,
    this.checksumUrl,
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

/// Self-update against the project's rolling GitHub "latest" release.
///  • Android → downloads the new APK and launches the system installer.
///  • Desktop → opens the release page to grab the new build (a running app
///    can't safely overwrite itself, esp. under the macOS sandbox).
///  • iOS → not possible (Apple forbids out-of-store self-update); we just link
///    to the release.
class Updater {
  Updater._();
  static final Updater instance = Updater._();

  static const _releaseApi =
      'https://api.github.com/repos/Talha-Ashraf420/Lumen-App/releases/latest';

  String get currentLabel =>
      kBuildNumber == 0 ? 'dev build' : 'Build $kBuildNumber';

  bool get canSelfInstall => !kIsWeb && Platform.isAndroid;

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

      String? apk;
      int? apkSize;
      String? apkSha256;
      String? checksumUrl;
      for (final a in (j['assets'] as List? ?? const [])) {
        if (a is! Map) continue;
        if ((a['name'] ?? '') == 'Lumen-Android.apk') {
          final url = '${a['browser_download_url'] ?? ''}';
          apk = url.isEmpty ? null : url;
          apkSize = int.tryParse('${a['size'] ?? ''}');
          final digest = '${a['digest'] ?? ''}';
          if (digest.startsWith('sha256:')) apkSha256 = digest.substring(7);
        } else if ((a['name'] ?? '') == 'Lumen-Android.apk.sha256') {
          final url = '${a['browser_download_url'] ?? ''}';
          checksumUrl = url.isEmpty ? null : url;
        }
      }
      return UpdateCheckResult.available(
        UpdateInfo(
          build: latest,
          name: name.isEmpty ? 'Build $latest' : name,
          notes: body.replaceFirst(RegExp(r'build:\s*\d+\s*'), '').trim(),
          apkUrl: apk,
          apkSize: apkSize,
          apkSha256: apkSha256,
          checksumUrl: checksumUrl,
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

  /// Android: download the APK with progress (0..1) then open the installer.
  /// Throws on failure.
  Future<void> downloadAndInstall(
    UpdateInfo info, {
    void Function(double)? onProgress,
  }) async {
    if (info.apkUrl == null) throw Exception('No Android build available.');
    final dir = await getTemporaryDirectory();
    final file = File('${dir.path}/lumen-update-${info.build}.apk');
    final client = http.Client();
    IOSink? sink;
    try {
      final resp = await client.send(
        http.Request('GET', Uri.parse(info.apkUrl!)),
      );
      if (resp.statusCode != 200) throw Exception('HTTP ${resp.statusCode}');
      final total = resp.contentLength ?? 0;
      var received = 0;
      sink = file.openWrite();
      await for (final chunk in resp.stream) {
        sink.add(chunk);
        received += chunk.length;
        if (total > 0) onProgress?.call(received / total);
      }
      await sink.flush();
      await sink.close();
      sink = null;
      if (total > 0 && received != total) {
        throw Exception('Update download ended early.');
      }
      if (info.apkSize != null &&
          info.apkSize! > 0 &&
          received != info.apkSize) {
        throw Exception('Update size does not match the release.');
      }
      final magic = await file
          .openRead(0, 4)
          .fold<List<int>>(<int>[], (a, b) => a..addAll(b));
      if (magic.length < 4 ||
          magic[0] != 0x50 ||
          magic[1] != 0x4b ||
          magic[2] != 0x03 ||
          magic[3] != 0x04) {
        throw Exception('Downloaded file is not a valid APK.');
      }
      var expected = info.apkSha256?.toLowerCase();
      if ((expected ?? '').isEmpty && (info.checksumUrl ?? '').isNotEmpty) {
        final checksum = await client
            .get(Uri.parse(info.checksumUrl!))
            .timeout(const Duration(seconds: 10));
        if (checksum.statusCode == 200) {
          expected = RegExp(
            r'\b[a-fA-F0-9]{64}\b',
          ).firstMatch(checksum.body)?.group(0)?.toLowerCase();
        }
      }
      if ((expected ?? '').isNotEmpty) {
        final actual = (await sha256.bind(file.openRead()).first).toString();
        if (actual != expected)
          throw Exception('Update checksum verification failed.');
      }
    } catch (_) {
      try {
        await sink?.close();
        if (await file.exists()) await file.delete();
      } catch (_) {}
      rethrow;
    } finally {
      client.close();
    }
    final r = await OpenFilex.open(
      file.path,
      type: 'application/vnd.android.package-archive',
    );
    if (r.type != ResultType.done) throw Exception(r.message);
  }

  Future<void> openReleasePage(UpdateInfo info) => launchUrl(
    Uri.parse(info.releaseUrl),
    mode: LaunchMode.externalApplication,
  );
}
