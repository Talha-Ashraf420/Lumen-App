import 'dart:convert';
import 'dart:io';
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
  final String releaseUrl; // fallback (desktop / iOS)
  UpdateInfo({required this.build, required this.name, required this.notes, required this.apkUrl, required this.releaseUrl});
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

  static const _releaseApi = 'https://api.github.com/repos/Talha-Ashraf420/Lumen-App/releases/latest';

  String get currentLabel => kBuildNumber == 0 ? 'dev build' : 'Build $kBuildNumber';

  bool get canSelfInstall => !kIsWeb && Platform.isAndroid;

  /// Returns update info if a newer build is published, else null.
  Future<UpdateInfo?> check() async {
    try {
      final res = await http
          .get(Uri.parse(_releaseApi), headers: {'Accept': 'application/vnd.github+json', 'User-Agent': 'Lumen'})
          .timeout(const Duration(seconds: 15));
      if (res.statusCode != 200) return null;
      final j = jsonDecode(res.body) as Map<String, dynamic>;
      final name = (j['name'] ?? '').toString();
      final body = (j['body'] ?? '').toString();
      final latest = _parseBuild(body) ?? _parseBuild(name);
      if (latest == null || latest <= kBuildNumber) return null;

      String? apk;
      for (final a in (j['assets'] as List? ?? const [])) {
        if ((a['name'] ?? '') == 'Lumen-Android.apk') apk = a['browser_download_url'];
      }
      return UpdateInfo(
        build: latest,
        name: name.isEmpty ? 'Build $latest' : name,
        notes: body.replaceFirst(RegExp(r'build:\s*\d+\s*'), '').trim(),
        apkUrl: apk,
        releaseUrl: (j['html_url'] ?? 'https://github.com/Talha-Ashraf420/Lumen-App/releases/latest').toString(),
      );
    } catch (_) {
      return null;
    }
  }

  int? _parseBuild(String s) {
    final m = RegExp(r'build:\s*(\d+)', caseSensitive: false).firstMatch(s) ?? RegExp(r'Build\s+(\d+)').firstMatch(s);
    return m == null ? null : int.tryParse(m.group(1)!);
  }

  /// Android: download the APK with progress (0..1) then open the installer.
  /// Throws on failure.
  Future<void> downloadAndInstall(UpdateInfo info, {void Function(double)? onProgress}) async {
    if (info.apkUrl == null) throw Exception('No Android build available.');
    final dir = await getTemporaryDirectory();
    final file = File('${dir.path}/lumen-update-${info.build}.apk');
    final client = http.Client();
    try {
      final resp = await client.send(http.Request('GET', Uri.parse(info.apkUrl!)));
      if (resp.statusCode >= 400) throw Exception('HTTP ${resp.statusCode}');
      final total = resp.contentLength ?? 0;
      var received = 0;
      final sink = file.openWrite();
      await for (final chunk in resp.stream) {
        sink.add(chunk);
        received += chunk.length;
        if (total > 0) onProgress?.call(received / total);
      }
      await sink.flush();
      await sink.close();
    } finally {
      client.close();
    }
    final r = await OpenFilex.open(file.path, type: 'application/vnd.android.package-archive');
    if (r.type != ResultType.done) throw Exception(r.message);
  }

  Future<void> openReleasePage(UpdateInfo info) =>
      launchUrl(Uri.parse(info.releaseUrl), mode: LaunchMode.externalApplication);
}
