import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'models.dart';
import 'resumable_transfer.dart';
import 'store.dart';

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
/// their local path. On Android a foreground transfer service continues after
/// the Flutter Activity closes; other platforms retain the in-app transport.
class Downloads extends ChangeNotifier with WidgetsBindingObserver {
  Downloads._();
  static final Downloads instance = Downloads._();

  final List<DownloadItem> items = [];
  Directory? _dir;
  static const _stateKey = 'lumen_downloads_index';
  final Map<String, http.Client> _active = {};
  final Set<String> _pausing = {}; // ids being paused (keep the partial file)
  final Set<String> _cancelling = {};
  static const _native = MethodChannel('lumen/downloads');
  final Set<String> _nativeTasks = {};
  Directory? _markerDir;
  Timer? _nativePoller;
  bool _nativeSyncing = false;
  bool _observing = false;
  int _lastNotify = 0;
  Future<void>? _loadFuture;
  String? _scope;
  int _activation = 0;
  bool _persisting = false;
  bool _persistAgain = false;
  Completer<void>? _persistDrain;

  // Most IPTV/Xtream accounts allow only one connection at a time, so a second
  // simultaneous download makes the provider drop the first. Run downloads
  // through a queue (one at a time) to avoid that.
  static const int maxConcurrent = 1;

  String? get folderPath => _dir?.path;

  Future<void> activate(XtreamCredentials? credentials) async {
    final activation = ++_activation;

    if (Platform.isAndroid && _scope != null) {
      try {
        await _native.invokeMethod<void>('pauseAll');
      } catch (_) {}
      _nativePoller?.cancel();
      _nativeTasks.clear();
    }

    // Finish pausing work under the old namespace before changing it. This
    // prevents a late download callback from writing account A's index into B.
    for (final entry in _active.entries.toList()) {
      _pausing.add(entry.key);
      entry.value.close();
    }
    for (final item in items) {
      if (item.status == DlStatus.queued) item.status = DlStatus.paused;
    }
    final deadline = DateTime.now().add(const Duration(seconds: 3));
    while (_active.isNotEmpty && DateTime.now().isBefore(deadline)) {
      await Future<void>.delayed(const Duration(milliseconds: 20));
    }
    if (_scope != null) await _persist();
    if (activation != _activation) return;

    _scope = credentials == null ? null : Store.profileScope(credentials);
    _loadFuture = null;
    items.clear();
    notifyListeners();
    if (_scope == null || activation != _activation) return;
    await (_loadFuture ??= _load(activation));
  }

  @Deprecated('Use activate(credentials) so state cannot cross profiles.')
  Future<void> load() async {
    if (_scope == null) return;
    await (_loadFuture ??= _load(_activation));
  }

  Future<void> _load(int activation) async {
    if (Platform.isAndroid && !_observing) {
      WidgetsBinding.instance.addObserver(this);
      _observing = true;
    }
    if (Platform.isAndroid) {
      _markerDir = Directory(
        '${(await getApplicationSupportDirectory()).path}/lumen-download-markers',
      );
    }
    // Prefer the user's real Downloads folder so files are browsable in Finder /
    // Explorer; fall back to the app documents dir (e.g. iOS) where it's null.
    Directory? base;
    try {
      base = await getDownloadsDirectory();
    } catch (_) {}
    base ??= await getApplicationDocumentsDirectory();
    _dir = Directory('${base.path}/Lumen');
    if (!await _dir!.exists()) await _dir!.create(recursive: true);
    final scope = _scope;
    if (scope == null || activation != _activation) return;
    final nativeStates = Platform.isAndroid ? await _nativeSnapshot() : null;
    final loaded = <DownloadItem>[];
    try {
      final legacyIndex = File('${_dir!.path}/index.json');
      var raw = await Store.readPrivate('${_stateKey}_$scope');
      final legacyPrivate = await Store.readPrivate(_stateKey);
      if (raw == null && legacyPrivate != null) {
        raw = legacyPrivate;
        await Store.writePrivate('${_stateKey}_$scope', raw);
        await Store.deletePrivate(_stateKey);
      }
      if (raw == null && await legacyIndex.exists()) {
        raw = await legacyIndex.readAsString();
        await Store.writePrivate('${_stateKey}_$scope', raw);
        await legacyIndex.delete();
      }
      if (raw != null) {
        final list = (jsonDecode(raw) as List)
            .map(
              (e) => DownloadItem.fromJson((e as Map).cast<String, dynamic>()),
            )
            .toList();
        // A completed Android service writes a small non-secret marker before
        // stopping. Its URL is never stored in the native job scheduler.
        for (final d in list) {
          final f = File(pathOf(d));
          final exists = await f.exists();
          if (Platform.isAndroid && exists && await _doneMarker(d).exists()) {
            d.status = DlStatus.completed;
            d.received = await f.length();
            d.total = d.received;
          } else if (Platform.isAndroid && await _failedMarker(d).exists()) {
            d.status = DlStatus.failed;
            d.errorMessage = await _failedMarker(d).readAsString();
          }
          if (d.status == DlStatus.completed) {
            if (exists) loaded.add(d);
            continue;
          }
          if (d.status == DlStatus.downloading || d.status == DlStatus.queued) {
            final native = nativeStates?[_nativeKey(d)];
            if (native != null) {
              d.status = native['status'] == 'queued'
                  ? DlStatus.queued
                  : DlStatus.downloading;
              _nativeTasks.add(_nativeKey(d));
            } else {
              d.status = DlStatus.paused;
            }
          }
          d.received = exists ? await f.length() : 0;
          loaded.add(d);
        }
      }
    } catch (_) {}
    if (scope != _scope || activation != _activation) return;
    items
      ..clear()
      ..addAll(loaded);
    await _persist();
    notifyListeners();
    if (_nativeTasks.isNotEmpty) _startNativePolling();
  }

  String _nativeKey(DownloadItem d) =>
      sha256.convert(utf8.encode('${_scope ?? ''}\u0000${d.id}')).toString();

  File _doneMarker(DownloadItem d) =>
      File('${_markerDir!.path}/${_nativeKey(d)}.done');

  File _failedMarker(DownloadItem d) =>
      File('${_markerDir!.path}/${_nativeKey(d)}.failed');

  Future<void> _clearMarker(DownloadItem d) async {
    if (_markerDir == null) return;
    try {
      final marker = _doneMarker(d);
      if (await marker.exists()) await marker.delete();
      final failed = _failedMarker(d);
      if (await failed.exists()) await failed.delete();
    } catch (_) {}
  }

  Future<Map<String, Map<String, dynamic>>?> _nativeSnapshot() async {
    try {
      final rows = await _native.invokeMethod<List<dynamic>>('snapshot');
      return {
        for (final row in rows ?? const [])
          if (row is Map && row['key'] is String)
            row['key'] as String: Map<String, dynamic>.from(row),
      };
    } catch (_) {
      return null;
    }
  }

  void _startNativePolling() {
    _nativePoller ??= Timer.periodic(
      const Duration(seconds: 1),
      (_) => unawaited(_syncNative()),
    );
  }

  Future<void> _syncNative() async {
    if (!Platform.isAndroid || _nativeSyncing || _scope == null) return;
    _nativeSyncing = true;
    final activation = _activation;
    try {
      final snapshot = await _nativeSnapshot();
      if (snapshot == null || activation != _activation) return;
      var changed = false;
      for (final d in items.toList()) {
        if (activation != _activation) return;
        final key = _nativeKey(d);
        if (!_nativeTasks.contains(key)) continue;
        final state = snapshot[key];
        if (state != null) {
          final nextStatus = state['status'] == 'queued'
              ? DlStatus.queued
              : DlStatus.downloading;
          final received = (state['received'] as num?)?.toInt() ?? d.received;
          final total = (state['total'] as num?)?.toInt() ?? d.total;
          if (d.status != nextStatus ||
              d.received != received ||
              d.total != total) {
            d.status = nextStatus;
            d.received = received;
            d.total = total;
            changed = true;
          }
        } else {
          _nativeTasks.remove(key);
          final file = File(pathOf(d));
          final done = await _doneMarker(d).exists();
          final exists = await file.exists();
          if (activation != _activation) return;
          if (done && exists) {
            d.status = DlStatus.completed;
            d.received = await file.length();
            d.total = d.received;
          } else if (await _failedMarker(d).exists()) {
            d.status = DlStatus.failed;
            d.errorMessage = await _failedMarker(d).readAsString();
            d.received = await file.exists() ? await file.length() : 0;
          } else {
            d.status = DlStatus.paused;
            d.received = await file.exists() ? await file.length() : 0;
          }
          changed = true;
        }
      }
      if (activation != _activation) return;
      if (changed) {
        _maybeNotify(force: true);
        await _persist();
      }
      if (_nativeTasks.isEmpty) {
        _nativePoller?.cancel();
        _nativePoller = null;
      }
    } finally {
      _nativeSyncing = false;
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) unawaited(_syncNative());
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
  bool isActive(String id) {
    final d = find(id);
    return _active.containsKey(id) ||
        (Platform.isAndroid &&
            d != null &&
            _nativeTasks.contains(_nativeKey(d)));
  }

  String? localPath(String id) {
    final d = find(id);
    return (d != null && d.status == DlStatus.completed) ? pathOf(d) : null;
  }

  Future<void> _persist() async {
    final scope = _scope;
    if (_dir == null || scope == null) return;
    if (_persisting) {
      _persistAgain = true;
      await _persistDrain?.future;
      return;
    }
    _persisting = true;
    final drain = Completer<void>();
    _persistDrain = drain;
    try {
      do {
        _persistAgain = false;
        final payload = jsonEncode(items.map((d) => d.toJson()).toList());
        await Store.writePrivate('${_stateKey}_$scope', payload);
      } while (_persistAgain);
    } catch (_) {
      // A later state transition will retry persistence.
    } finally {
      _persisting = false;
      if (!drain.isCompleted) drain.complete();
      if (identical(_persistDrain, drain)) _persistDrain = null;
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
    if (_dir == null && _scope != null) {
      await (_loadFuture ??= _load(_activation));
    }
    final scope = _scope;
    if (scope == null) return;
    final existing = find(id);
    if (existing != null && existing.status != DlStatus.failed) {
      return; // already downloaded/queued/active
    }
    if (existing != null) await _deleteFile(existing);
    final rel =
        '$scope/${relativePathFor(id: id, title: title, kind: kind, ext: ext)}';
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
    if (Platform.isAndroid) {
      for (final d in items.where((item) => item.status == DlStatus.queued)) {
        final key = _nativeKey(d);
        if (_nativeTasks.add(key)) unawaited(_enqueueNative(d, key));
      }
      return;
    }
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

  Future<void> _enqueueNative(DownloadItem d, String key) async {
    final activation = _activation;
    await _clearMarker(d);
    try {
      final accepted = await _native.invokeMethod<bool>('enqueue', {
        'key': key,
        'url': d.remoteUrl,
        'path': pathOf(d),
        'title': d.title,
      });
      if (accepted != true) throw StateError('The download could not start.');
      if (activation != _activation || !_nativeTasks.contains(key)) {
        await _native.invokeMethod<void>('pause', key);
        return;
      }
      _startNativePolling();
      await _syncNative();
    } catch (_) {
      if (activation != _activation || !_nativeTasks.contains(key)) return;
      _nativeTasks.remove(key);
      d.status = DlStatus.failed;
      d.errorMessage = 'The Android download service could not start.';
      await _persist();
      _maybeNotify(force: true);
    }
  }

  Future<void> _run(DownloadItem d) async {
    final client = http.Client();
    _active[d.id] = client;
    d.status = DlStatus.downloading;
    d.errorMessage = null;
    await _persist();
    _maybeNotify(force: true);
    final file = File(pathOf(d));
    try {
      final result = await downloadResumable(
        uri: Uri.parse(d.remoteUrl),
        file: file,
        isInterrupted: () =>
            !_active.containsKey(d.id) ||
            _pausing.contains(d.id) ||
            _cancelling.contains(d.id),
        onClient: (next) => _active[d.id] = next,
        onProgress: (received, total) {
          d.received = received;
          d.total = total;
          _maybeNotify();
        },
      );
      d.received = result.received;
      d.total = result.total;
      d.status = DlStatus.completed;
      await _persist();
    } catch (error) {
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
    if (error is TransferPermanentFailure) return error.message;
    final message = error.toString();
    final httpStatus = RegExp(r'HTTP ([0-9]{3})').firstMatch(message)?.group(1);
    if (httpStatus != null) return 'Provider returned HTTP $httpStatus.';
    if (message.contains('ended early')) {
      return 'Connection ended before the file was complete.';
    }
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
    if (Platform.isAndroid) {
      final key = _nativeKey(d);
      _nativeTasks.remove(key);
      unawaited(_native.invokeMethod<void>('pause', key));
      d.status = DlStatus.paused;
      notifyListeners();
      unawaited(_persist());
      return;
    }
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
        (d.status != DlStatus.paused && d.status != DlStatus.failed)) {
      return;
    }
    d.status = DlStatus.queued;
    d.errorMessage = null;
    notifyListeners();
    unawaited(_persist());
    _pump();
  }

  void cancel(String id) {
    final d = find(id);
    if (d == null) return;
    if (Platform.isAndroid) {
      final key = _nativeKey(d);
      _nativeTasks.remove(key);
      unawaited(() async {
        try {
          await _native.invokeMethod<void>('cancel', key);
        } catch (_) {}
        await _deleteFile(d);
      }());
      items.remove(d);
      notifyListeners();
      unawaited(_persist());
      return;
    }
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
    await _clearMarker(d);
    try {
      final f = File(pathOf(d));
      if (await f.exists()) await f.delete();
    } catch (_) {}
  }

  Future<void> delete(DownloadItem d) async {
    if (Platform.isAndroid) {
      final key = _nativeKey(d);
      _nativeTasks.remove(key);
      try {
        await _native.invokeMethod<void>('cancel', key);
      } catch (_) {}
      await _deleteFile(d);
      items.remove(d);
      notifyListeners();
      await _persist();
      return;
    }
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
