import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

enum DlStatus { queued, downloading, paused, completed, failed }

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
  final Set<String> _pausing = {}; // ids being paused (keep the partial file)
  int _lastNotify = 0;

  // Most IPTV/Xtream accounts allow only one connection at a time, so a second
  // simultaneous download makes the provider drop the first. Run downloads
  // through a queue (one at a time) to avoid that.
  static const int maxConcurrent = 1;

  String? get folderPath => _dir?.path;

  Future<void> load() async {
    // Prefer the user's real Downloads folder so files are browsable in Finder /
    // Explorer; fall back to the app documents dir (e.g. iOS) where it's null.
    Directory? base;
    try {
      base = await getDownloadsDirectory();
    } catch (_) {}
    base ??= await getApplicationDocumentsDirectory();
    _dir = Directory('${base.path}/Lumen');
    if (!await _dir!.exists()) await _dir!.create(recursive: true);
    try {
      final index = File('${_dir!.path}/index.json');
      if (await index.exists()) {
        final list = (jsonDecode(await index.readAsString()) as List)
            .map((e) => DownloadItem.fromJson((e as Map).cast<String, dynamic>()))
            .toList();
        // Restore completed files, and paused downloads (resync received from the
        // partial file on disk); drop anything whose file vanished.
        for (final d in list) {
          final f = File(pathOf(d));
          if (!await f.exists()) continue;
          if (d.status == DlStatus.completed) {
            items.add(d);
          } else if (d.status == DlStatus.paused) {
            d.received = await f.length();
            items.add(d);
          }
        }
      }
    } catch (_) {}
    notifyListeners();
  }

  String pathOf(DownloadItem d) => '${_dir!.path}/${d.fileName}';

  static String _sanitize(String s) {
    var t = s.replaceAll(RegExp(r'[\\/:*?"<>|]'), ' ').replaceAll(RegExp(r'\s+'), ' ').trim();
    if (t.length > 120) t = t.substring(0, 120).trim();
    return t.isEmpty ? 'file' : t;
  }

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
      await File('${_dir!.path}/index.json').writeAsString(jsonEncode(items
          .where((d) => d.status == DlStatus.completed || d.status == DlStatus.paused)
          .map((d) => d.toJson())
          .toList()));
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
    final existing = find(id);
    if (existing != null && existing.status != DlStatus.failed) return; // already downloaded/queued/active
    final safeExt = ext.replaceAll(RegExp(r'[^a-zA-Z0-9]'), '');
    final e = safeExt.isEmpty ? 'mp4' : safeExt;
    // Organize into Movies/ and Series/<show>/ with human-readable filenames.
    final parts = title.split(' · ');
    final String rel;
    if (kind == 'episode' && parts.length > 1) {
      rel = 'Series/${_sanitize(parts.first)}/${_sanitize(parts.sublist(1).join(' · '))}.$e';
    } else {
      rel = 'Movies/${_sanitize(title)}.$e';
    }
    final d = DownloadItem(
      id: id,
      title: title,
      poster: poster,
      kind: kind,
      remoteUrl: remoteUrl,
      fileName: rel,
      progressKey: progressKey,
      status: DlStatus.queued,
    );
    items.removeWhere((x) => x.id == id && x.status == DlStatus.failed); // clear a prior failed entry
    items.insert(0, d);
    notifyListeners();
    _pump();
  }

  /// Start queued downloads up to the concurrency limit.
  void _pump() {
    if (_active.length >= maxConcurrent) return;
    // Oldest queued first (items are inserted at the front, so scan from the end).
    DownloadItem? next;
    for (var i = items.length - 1; i >= 0; i--) {
      if (items[i].status == DlStatus.queued) {
        next = items[i];
        break;
      }
    }
    if (next == null) return;
    _run(next);
    if (_active.length < maxConcurrent) _pump(); // fill remaining slots
  }

  Future<void> _run(DownloadItem d) async {
    final client = http.Client();
    _active[d.id] = client;
    d.status = DlStatus.downloading;
    _maybeNotify(force: true);
    IOSink? sink;
    final file = File(pathOf(d));
    try {
      await file.parent.create(recursive: true); // ensure Movies//Series/<show>/ exists
      // Resume: if a partial file exists, continue from its current size.
      var startAt = 0;
      if (await file.exists()) {
        final len = await file.length();
        if (len > 0 && (d.total == 0 || len < d.total)) startAt = len;
      }
      final req = http.Request('GET', Uri.parse(d.remoteUrl))..headers['User-Agent'] = 'VLC/3.0.20 LibVLC/3.0.20';
      if (startAt > 0) req.headers['range'] = 'bytes=$startAt-';
      final resp = await client.send(req);
      if (resp.statusCode >= 400) throw Exception('HTTP ${resp.statusCode}');
      if (startAt > 0 && resp.statusCode == 206) {
        // Server honored the range — append to the partial file.
        d.received = startAt;
        final cl = resp.contentLength ?? 0;
        d.total = cl > 0 ? startAt + cl : d.total;
        sink = file.openWrite(mode: FileMode.append);
      } else {
        // No range support (or fresh) — (re)start from the beginning.
        d.received = 0;
        d.total = resp.contentLength ?? 0;
        sink = file.openWrite();
      }
      await for (final chunk in resp.stream) {
        if (!_active.containsKey(d.id)) {
          // stopped — either paused (keep partial) or cancelled (delete)
          await sink!.flush();
          await sink.close();
          sink = null;
          if (_pausing.remove(d.id)) {
            d.status = DlStatus.paused;
            await _persist();
          } else {
            await file.delete().catchError((_) => file);
            items.remove(d);
          }
          notifyListeners();
          return;
        }
        sink!.add(chunk);
        d.received += chunk.length;
        _maybeNotify();
      }
      await sink!.flush();
      await sink.close();
      sink = null;
      d.status = DlStatus.completed;
      await _persist();
    } catch (_) {
      try {
        await sink?.close();
      } catch (_) {}
      // Keep the partial on failure so it can be resumed; mark failed.
      d.status = DlStatus.failed;
    } finally {
      _active.remove(d.id);
      _pausing.remove(d.id);
      client.close();
      _maybeNotify(force: true);
      _pump(); // start the next queued download
    }
  }

  /// Pause an active or queued download, keeping any partial bytes.
  void pause(String id) {
    final d = find(id);
    if (d == null) return;
    if (_active.containsKey(id)) {
      _pausing.add(id);
      _active.remove(id); // loop stops, keeps the partial, marks paused
    } else if (d.status == DlStatus.queued) {
      d.status = DlStatus.paused;
    }
    notifyListeners();
    _pump();
  }

  /// Resume a paused or failed download (re-queues; _run continues via Range).
  void resume(String id) {
    final d = find(id);
    if (d == null || (d.status != DlStatus.paused && d.status != DlStatus.failed)) return;
    d.status = DlStatus.queued;
    notifyListeners();
    _pump();
  }

  void cancel(String id) {
    final d = find(id);
    if (d == null) return;
    if (_active.containsKey(id)) {
      _pausing.remove(id); // ensure the loop treats this as a cancel (delete)
      _active.remove(id);
    } else {
      _deleteFile(d);
      items.remove(d);
    }
    notifyListeners();
    _persist();
    _pump();
  }

  Future<void> _deleteFile(DownloadItem d) async {
    try {
      final f = File(pathOf(d));
      if (await f.exists()) await f.delete();
    } catch (_) {}
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
    _pump();
  }

  int get completedCount => items.where((d) => d.status == DlStatus.completed).length;
}
