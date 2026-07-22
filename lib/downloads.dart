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
  String? errorMessage;

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
    this.errorMessage,
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
        if (errorMessage != null) 'errorMessage': errorMessage,
  };

  factory DownloadItem.fromJson(Map<String, dynamic> j) => DownloadItem(
    id: j['id'],
    title: j['title'] ?? '',
    poster: j['poster'] ?? '',
    kind: j['kind'] ?? 'movie',
    remoteUrl: j['remoteUrl'] ?? '',
    fileName: j['fileName'] ?? '',
    progressKey: j['progressKey'],
    status: DlStatus.values.firstWhere(
      (s) => s.name == j['status'],
      orElse: () => DlStatus.completed,
    ),
    received: j['received'] ?? 0,
        total: j['total'] ?? 0,
        errorMessage: j['errorMessage'],
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
  final Set<String> _cancelling = {};
  int _lastNotify = 0;
  Future<void>? _loadFuture;
  bool _persisting = false;
  bool _persistAgain = false;

  // Most IPTV/Xtream accounts allow only one connection at a time, so a second
  // simultaneous download makes the provider drop the first. Run downloads
  // through a queue (one at a time) to avoid that.
  static const int maxConcurrent = 1;

  String? get folderPath => _dir?.path;

  Future<void> load() => _loadFuture ??= _load();

  Future<void> _load() async {
    // Prefer the user's real Downloads folder so files are browsable in Finder /
    // Explorer; fall back to the app documents dir (e.g. iOS) where it's null.
    Directory? base;
    try {
      base = await getDownloadsDirectory();
    } catch (_) {}
    base ??= await getApplicationDocumentsDirectory();
    _dir = Directory('${base.path}/Lumen');
    if (!await _dir!.exists()) await _dir!.create(recursive: true);
    items.clear();
    try {
      final index = File('${_dir!.path}/index.json');
      if (await index.exists()) {
        final list = (jsonDecode(await index.readAsString()) as List)
            .map(
              (e) => DownloadItem.fromJson((e as Map).cast<String, dynamic>()),
            )
            .toList();
        // Active work cannot survive process termination. Restore it as paused
        // so the user can deliberately resume without losing partial bytes.
        for (final d in list) {
          final f = File(pathOf(d));
          final exists = await f.exists();
          if (d.status == DlStatus.completed) {
            if (exists) items.add(d);
            continue;
          }
          if (d.status == DlStatus.downloading || d.status == DlStatus.queued) {
            d.status = DlStatus.paused;
          }
          d.received = exists ? await f.length() : 0;
          items.add(d);
        }
      }
    } catch (_) {}
    await _persist();
    notifyListeners();
  }

  String pathOf(DownloadItem d) => '${_dir!.path}/${d.fileName}';

  static String _sanitize(String s) {
    var t = s
        .replaceAll(RegExp(r'[\\/:*?"<>|]'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    if (t.length > 120) t = t.substring(0, 120).trim();
    return t.isEmpty ? 'file' : t;
  }

  static String _idSuffix(String id) {
    final safe = id.replaceAll(RegExp(r'[^a-zA-Z0-9_-]'), '_');
    return safe.length <= 36 ? safe : safe.substring(safe.length - 36);
  }

  static String relativePathFor({
    required String id,
    required String title,
    required String kind,
    required String ext,
  }) {
    final safeExt = ext.replaceAll(RegExp(r'[^a-zA-Z0-9]'), '');
    final extension = safeExt.isEmpty ? 'mp4' : safeExt;
    final parts = title.split(' · ');
    if (kind == 'episode' && parts.length > 1) {
      return 'Series/${_sanitize(parts.first)}/'
          '${_sanitize(parts.sublist(1).join(' · '))}-${_idSuffix(id)}.$extension';
    }
    return 'Movies/${_sanitize(title)}-${_idSuffix(id)}.$extension';
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
    if (_persisting) {
      _persistAgain = true;
      return;
    }
    _persisting = true;
    try {
      do {
        _persistAgain = false;
        final payload = jsonEncode(items.map((d) => d.toJson()).toList());
        final index = File('${_dir!.path}/index.json');
        final temp = File('${index.path}.tmp');
        await temp.writeAsString(payload, flush: true);
        if (await index.exists()) await index.delete();
        await temp.rename(index.path);
      } while (_persistAgain);
    } catch (_) {
      // A later state transition will retry persistence.
    } finally {
      _persisting = false;
    }
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
    if (existing != null && existing.status != DlStatus.failed)
      return; // already downloaded/queued/active
    if (existing != null) await _deleteFile(existing);
    final rel = relativePathFor(
      id: id,
      title: title,
      kind: kind,
      ext: ext,
    );
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
    items.removeWhere(
      (x) => x.id == id && x.status == DlStatus.failed,
    ); // clear a prior failed entry
    items.insert(0, d);
    await _persist();
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
    d.errorMessage = null;
    await _persist();
    _maybeNotify(force: true);
    IOSink? sink;
    final file = File(pathOf(d));
    try {
      await file.parent.create(
        recursive: true,
      ); // ensure Movies//Series/<show>/ exists
      // Resume: if a partial file exists, continue from its current size.
      var startAt = 0;
      if (await file.exists()) {
        final len = await file.length();
        if (len > 0 && (d.total == 0 || len < d.total)) startAt = len;
      }
      final req = http.Request('GET', Uri.parse(d.remoteUrl))
        ..headers['User-Agent'] = 'VLC/3.0.20 LibVLC/3.0.20';
      if (startAt > 0) req.headers['range'] = 'bytes=$startAt-';
      final resp = await client.send(req);
      if (resp.statusCode != 200 && resp.statusCode != 206) {
        throw Exception('HTTP ${resp.statusCode}');
      }
      if (startAt > 0 && resp.statusCode == 206) {
        // Server honored the range — append to the partial file.
        d.received = startAt;
        final cl = resp.contentLength ?? 0;
        final rangeTotal = int.tryParse(
          RegExp(
                r'/([0-9]+)$',
              ).firstMatch(resp.headers['content-range'] ?? '')?.group(1) ??
              '',
        );
        d.total = rangeTotal ?? (cl > 0 ? startAt + cl : d.total);
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
          await _finishRequestedStop(d, file);
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
      if (d.total > 0 && d.received != d.total) {
        throw Exception(
          'Download ended early (${d.received}/${d.total} bytes).',
        );
      }
      d.status = DlStatus.completed;
      await _persist();
    } catch (error) {
      try {
        await sink?.close();
      } catch (_) {}
      if (_pausing.contains(d.id) || _cancelling.contains(d.id)) {
        await _finishRequestedStop(d, file);
      } else {
        // Keep the partial on failure so it can be resumed.
        d.status = DlStatus.failed;
        d.errorMessage = _friendlyError(error);
        if (await file.exists()) d.received = await file.length();
        await _persist();
      }
    } finally {
      _active.remove(d.id);
      _pausing.remove(d.id);
      _cancelling.remove(d.id);
      client.close();
      _maybeNotify(force: true);
      _pump(); // start the next queued download
    }
  }

  String _friendlyError(Object error) {
    final message = error.toString();
    final httpStatus = RegExp(r'HTTP ([0-9]{3})').firstMatch(message)?.group(1);
    if (httpStatus != null) return 'Provider returned HTTP $httpStatus.';
    if (message.contains('ended early')) return 'Connection ended before the file was complete.';
    if (error is FormatException) return 'The download URL is invalid.';
    return 'Connection interrupted. Resume to try again.';
  }

  Future<void> _finishRequestedStop(DownloadItem d, File file) async {
    if (_pausing.remove(d.id)) {
      d.status = DlStatus.paused;
      if (await file.exists()) d.received = await file.length();
    } else if (_cancelling.remove(d.id)) {
      try {
        if (await file.exists()) await file.delete();
      } catch (_) {}
      items.remove(d);
    }
    await _persist();
  }

  /// Pause an active or queued download, keeping any partial bytes.
  void pause(String id) {
    final d = find(id);
    if (d == null) return;
    if (_active.containsKey(id)) {
      _pausing.add(id);
      d.status = DlStatus.paused;
      _active.remove(id)?.close();
    } else if (d.status == DlStatus.queued) {
      d.status = DlStatus.paused;
    }
    notifyListeners();
    unawaited(_persist());
    _pump();
  }

  /// Resume a paused or failed download (re-queues; _run continues via Range).
  void resume(String id) {
    final d = find(id);
    if (d == null ||
        (d.status != DlStatus.paused && d.status != DlStatus.failed))
      return;
    d.status = DlStatus.queued;
    d.errorMessage = null;
    notifyListeners();
    unawaited(_persist());
    _pump();
  }

  void cancel(String id) {
    final d = find(id);
    if (d == null) return;
    if (_active.containsKey(id)) {
      _pausing.remove(id); // ensure the loop treats this as a cancel (delete)
      _cancelling.add(id);
      items.remove(d);
      _active.remove(id)?.close();
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
    if (_active.containsKey(d.id)) {
      _pausing.remove(d.id);
      _cancelling.add(d.id);
      items.remove(d);
      _active.remove(d.id)?.close();
      notifyListeners();
      await _persist();
      _pump();
      return;
    }
    try {
      final f = File(pathOf(d));
      if (await f.exists()) await f.delete();
    } catch (_) {}
    items.remove(d);
    notifyListeners();
    await _persist();
    _pump();
  }

  int get completedCount =>
      items.where((d) => d.status == DlStatus.completed).length;
}
