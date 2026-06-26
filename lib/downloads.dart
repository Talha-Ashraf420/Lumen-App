import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

enum DlStatus { downloading, completed, failed }

class DownloadItem {
  final String id; // 'movie:123' / 'ep:456'
  final String title;
  final String poster;
  final String kind; // 'movie' | 'episode'
  final String remoteUrl;
  final String fileName;
  final String? progressKey; // shares continue-watching with the streamed copy
  DlStatus status;
  int received;
  int total;

  DownloadItem({
    required this.id,
    required this.title,
    required this.poster,
    required this.kind,
    required this.remoteUrl,
    required this.fileName,
    required this.progressKey,
    this.status = DlStatus.downloading,
    this.received = 0,
    this.total = 0,
  });

  double get progress => total > 0 ? (received / total).clamp(0.0, 1.0) : 0;

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'poster': poster,
        'kind': kind,
        'remoteUrl': remoteUrl,
        'fileName': fileName,
        'progressKey': progressKey,
        'status': status.name,
        'received': received,
        'total': total,
      };

  factory DownloadItem.fromJson(Map<String, dynamic> j) => DownloadItem(
        id: j['id'],
        title: j['title'] ?? '',
        poster: j['poster'] ?? '',
        kind: j['kind'] ?? 'movie',
        remoteUrl: j['remoteUrl'] ?? '',
        fileName: j['fileName'] ?? '',
        progressKey: j['progressKey'],
        status: DlStatus.values.firstWhere((s) => s.name == j['status'], orElse: () => DlStatus.completed),
        received: j['received'] ?? 0,
        total: j['total'] ?? 0,
      );
}

/// Offline downloads of the user's own VOD (movies / series episodes). Streams
/// the provider's direct media URL to a local file in the app's documents dir,
/// tracking progress. Downloaded files play back through the normal player via
/// their local path. In-app only (downloads run while the app is open).
class Downloads extends ChangeNotifier {
  Downloads._();
  static final Downloads instance = Downloads._();

  final List<DownloadItem> items = [];
  Directory? _dir;
  final Map<String, http.Client> _active = {};
  int _lastNotify = 0;

  Future<void> load() async {
    final base = await getApplicationDocumentsDirectory();
    _dir = Directory('${base.path}/lumen_downloads');
    if (!await _dir!.exists()) await _dir!.create(recursive: true);
    try {
      final index = File('${_dir!.path}/index.json');
      if (await index.exists()) {
        final list = (jsonDecode(await index.readAsString()) as List)
            .map((e) => DownloadItem.fromJson((e as Map).cast<String, dynamic>()))
            .toList();
        // Keep only completed entries whose file still exists; drop partials.
        for (final d in list) {
          if (d.status == DlStatus.completed && await File(pathOf(d)).exists()) items.add(d);
        }
      }
    } catch (_) {}
    notifyListeners();
  }

  String pathOf(DownloadItem d) => '${_dir!.path}/${d.fileName}';

  DownloadItem? find(String id) {
    for (final d in items) {
      if (d.id == id) return d;
    }
    return null;
  }

  bool isDownloaded(String id) => find(id)?.status == DlStatus.completed;
  bool isActive(String id) => _active.containsKey(id);

  String? localPath(String id) {
    final d = find(id);
    return (d != null && d.status == DlStatus.completed) ? pathOf(d) : null;
  }

  Future<void> _persist() async {
    if (_dir == null) return;
    try {
      await File('${_dir!.path}/index.json')
          .writeAsString(jsonEncode(items.where((d) => d.status == DlStatus.completed).map((d) => d.toJson()).toList()));
    } catch (_) {}
  }

  void _maybeNotify({bool force = false}) {
    final now = DateTime.now().millisecondsSinceEpoch;
    if (force || now - _lastNotify > 400) {
      _lastNotify = now;
      notifyListeners();
    }
  }

  Future<void> start({
    required String id,
    required String title,
    required String poster,
    required String kind,
    required String remoteUrl,
    required String ext,
    String? progressKey,
  }) async {
    if (_dir == null) await load();
    if (isDownloaded(id) || isActive(id)) return;
    final safeExt = ext.replaceAll(RegExp(r'[^a-zA-Z0-9]'), '');
    final d = DownloadItem(
      id: id,
      title: title,
      poster: poster,
      kind: kind,
      remoteUrl: remoteUrl,
      fileName: '${id.replaceAll(RegExp(r'[^a-zA-Z0-9]'), '_')}.${safeExt.isEmpty ? 'mp4' : safeExt}',
      progressKey: progressKey,
    );
    items.removeWhere((x) => x.id == id); // clear any prior failed entry
    items.insert(0, d);
    notifyListeners();

    final client = http.Client();
    _active[id] = client;
    IOSink? sink;
    final file = File(pathOf(d));
    try {
      final resp = await client.send(http.Request('GET', Uri.parse(remoteUrl))
        ..headers['User-Agent'] = 'VLC/3.0.20 LibVLC/3.0.20');
      if (resp.statusCode >= 400) throw Exception('HTTP ${resp.statusCode}');
      d.total = resp.contentLength ?? 0;
      sink = file.openWrite();
      await for (final chunk in resp.stream) {
        if (!_active.containsKey(id)) {
          // cancelled
          await sink.close();
          await file.delete().catchError((_) => file);
          items.remove(d);
          notifyListeners();
          return;
        }
        sink.add(chunk);
        d.received += chunk.length;
        _maybeNotify();
      }
      await sink.flush();
      await sink.close();
      sink = null;
      d.status = DlStatus.completed;
      _maybeNotify(force: true);
      await _persist();
    } catch (_) {
      try {
        await sink?.close();
      } catch (_) {}
      try {
        await file.delete();
      } catch (_) {}
      d.status = DlStatus.failed;
      _maybeNotify(force: true);
    } finally {
      _active.remove(id);
      client.close();
    }
  }

  void cancel(String id) {
    // The download loop notices the missing client and cleans up.
    _active.remove(id);
    notifyListeners();
  }

  Future<void> delete(DownloadItem d) async {
    _active.remove(d.id);
    try {
      final f = File(pathOf(d));
      if (await f.exists()) await f.delete();
    } catch (_) {}
    items.remove(d);
    notifyListeners();
    await _persist();
  }

  int get completedCount => items.where((d) => d.status == DlStatus.completed).length;
}
