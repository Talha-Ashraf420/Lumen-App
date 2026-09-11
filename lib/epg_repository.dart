import 'dart:async';
import 'dart:collection';

import 'package:flutter/foundation.dart';

import 'catalog_store.dart';
import 'channel_logos.dart';
import 'epg.dart';
import 'epg_loader.dart';
import 'models.dart';
import 'store.dart';
import 'xtream.dart';

const String kXtreamShortEpgSource = 'xtream-short-v1';

class EpgNowNext {
  const EpgNowNext({this.now, this.next});

  final EpgProgramme? now;
  final EpgProgramme? next;
}

/// Account-scoped, cache-first EPG coordinator used by Live and Guide.
///
/// The queue deliberately permits only two provider calls at once. Widgets
/// submit visible channels, not complete provider catalogs, and duplicate work
/// is collapsed before it reaches the network.
class EpgRepository extends ChangeNotifier {
  EpgRepository({
    required this.client,
    CatalogStore? store,
    DateTime Function()? clock,
  }) : store = store ?? CatalogStore.instance,
       _clock = clock ?? DateTime.now,
       profileScope = Store.profileScope(client.creds);

  static const int maxConcurrentShortRequests = 2;
  static const Duration shortFreshness = Duration(minutes: 10);
  static const Duration negativeFreshness = Duration(minutes: 2);
  static const Duration xmltvFreshness = Duration(hours: 6);

  final XtreamClient client;
  final CatalogStore store;
  final String profileScope;
  final DateTime Function() _clock;
  final Queue<LiveStream> _queue = Queue<LiveStream>();
  final Set<int> _queued = <int>{};
  final Set<int> _loading = <int>{};
  final Map<int, DateTime> _freshUntil = <int, DateTime>{};
  final Map<int, List<EpgProgramme>> _programmes = <int, List<EpgProgramme>>{};
  Future<void>? _guideSync;
  int _visibleRevision = 0;
  bool _disposed = false;
  bool _guideRefreshing = false;
  String _guideStatus = '';

  bool get guideRefreshing => _guideRefreshing;
  String get guideStatus => _guideStatus;
  int get shortRequestsInFlight => _loading.length;

  bool isLoading(int streamId) => _loading.contains(streamId);

  EpgNowNext nowNextFor(int streamId, {DateTime? at}) {
    final time = (at ?? _clock()).toUtc();
    final values = _programmes[streamId] ?? const <EpgProgramme>[];
    EpgProgramme? current;
    EpgProgramme? next;
    for (final programme in values) {
      if (!programme.startUtc.isAfter(time) &&
          programme.stopUtc.isAfter(time)) {
        current = programme;
        continue;
      }
      if (programme.startUtc.isAfter(time) &&
          (next == null || programme.startUtc.isBefore(next.startUtc))) {
        next = programme;
      }
    }
    return EpgNowNext(now: current, next: next);
  }

  /// Prime cached rows and enqueue only the supplied visible/overscan window.
  Future<void> primeVisible(Iterable<LiveStream> channels) async {
    final unique = <int, LiveStream>{
      for (final channel in channels) channel.streamId: channel,
    }.values.toList(growable: false);
    final revision = ++_visibleRevision;
    final visibleIds = unique.map((channel) => channel.streamId).toSet();
    _queue.removeWhere((channel) => !visibleIds.contains(channel.streamId));
    _queued.removeWhere((streamId) => !visibleIds.contains(streamId));
    if (unique.isEmpty || _disposed) return;

    await _prime(unique, visibleRevision: revision);
  }

  Future<void> _prime(List<LiveStream> channels, {int? visibleRevision}) async {
    if (channels.isEmpty || _disposed) return;

    final now = _clock().toUtc();
    try {
      final cached = await store.epgWindow(
        profileScope,
        kXtreamShortEpgSource,
        channelKeys: [for (final channel in channels) '${channel.streamId}'],
        startUtc: now.subtract(const Duration(hours: 6)),
        endUtc: now.add(const Duration(hours: 12)),
      );
      if (_disposed) return;
      final grouped = <int, List<EpgProgramme>>{};
      for (final programme in cached) {
        final id = int.tryParse(programme.channelKey);
        if (id != null) (grouped[id] ??= <EpgProgramme>[]).add(programme);
      }
      var changed = false;
      for (final entry in grouped.entries) {
        entry.value.sort((a, b) => a.startUtc.compareTo(b.startUtc));
        _programmes[entry.key] = List.unmodifiable(entry.value);
        final current = nowNextFor(entry.key, at: now).now;
        if (current != null) {
          final cap = now.add(shortFreshness);
          _freshUntil[entry.key] = current.stopUtc.isBefore(cap)
              ? current.stopUtc
              : cap;
        }
        changed = true;
      }
      if (changed) notifyListeners();
    } catch (_) {
      // SQLite cache failure must not block channels or provider fallback.
    }

    // M3U has no per-channel short-EPG endpoint. Reuse a previously cached
    // XMLTV generation for the visible window; opening Live must never trigger
    // a full guide download.
    if (client.creds.isM3u) {
      try {
        final cachedGuide = await guideWindow(
          channels,
          startUtc: now.subtract(const Duration(hours: 6)),
          endUtc: now.add(const Duration(hours: 12)),
        );
        if (_disposed) return;
        var changed = false;
        for (final channel in channels) {
          final values = cachedGuide[channel.streamId] ?? const [];
          if (values.isEmpty) continue;
          _programmes[channel.streamId] = List.unmodifiable(values);
          changed = true;
        }
        if (changed) notifyListeners();
      } catch (_) {
        // Cached guide metadata is optional and must not block Live.
      }
      return;
    }
    if (client.creds.isDemo ||
        (visibleRevision != null && visibleRevision != _visibleRevision)) {
      return;
    }
    for (final channel in channels) {
      _enqueue(channel, now);
    }
    _pump();
  }

  Future<void> primeChannel(LiveStream channel) => _prime([channel]);

  void _enqueue(LiveStream channel, DateTime now) {
    final freshUntil = _freshUntil[channel.streamId];
    if ((freshUntil?.isAfter(now) ?? false) ||
        _loading.contains(channel.streamId) ||
        !_queued.add(channel.streamId)) {
      return;
    }
    _queue.add(channel);
  }

  void _pump() {
    while (!_disposed &&
        _loading.length < maxConcurrentShortRequests &&
        _queue.isNotEmpty) {
      final channel = _queue.removeFirst();
      _queued.remove(channel.streamId);
      _loading.add(channel.streamId);
      notifyListeners();
      unawaited(_fetchShort(channel));
    }
  }

  Future<void> _fetchShort(LiveStream channel) async {
    final fetchedAt = _clock().toUtc();
    try {
      final values = await client.shortEpg(channel.streamId, limit: 4);
      if (_disposed) return;
      final normalized = [
        for (final programme in values)
          EpgProgramme(
            channelKey: '${channel.streamId}',
            startUtc: programme.startUtc,
            stopUtc: programme.stopUtc,
            title: programme.title,
            subtitle: programme.subtitle,
            description: programme.description,
            categories: programme.categories,
            icon: programme.icon,
            hasArchive: programme.hasArchive,
            catchupId: programme.catchupId,
            stopInferred: programme.stopInferred,
          ),
      ]..sort((a, b) => a.startUtc.compareTo(b.startUtc));
      _programmes[channel.streamId] = List.unmodifiable(normalized);
      await store.replaceShortEpgChannel(
        profileScope,
        kXtreamShortEpgSource,
        '${channel.streamId}',
        normalized,
        fetchedAt: fetchedAt,
      );
      final current = nowNextFor(channel.streamId, at: fetchedAt).now;
      final maximum = fetchedAt.add(shortFreshness);
      _freshUntil[channel.streamId] = current == null
          ? fetchedAt.add(negativeFreshness)
          : current.stopUtc.isBefore(maximum)
          ? current.stopUtc
          : maximum;
    } catch (_) {
      // Per-channel misses are intentionally quiet and negatively cached.
      _freshUntil[channel.streamId] = fetchedAt.add(negativeFreshness);
    } finally {
      _loading.remove(channel.streamId);
      if (!_disposed) {
        notifyListeners();
        _pump();
      }
    }
  }

  /// Refresh stale XMLTV sources once and keep all status inline in Guide.
  Future<void> ensureFullGuide({bool force = false}) {
    final active = _guideSync;
    if (active != null) return active;
    final future = _ensureFullGuide(force: force);
    _guideSync = future.whenComplete(() => _guideSync = null);
    return _guideSync!;
  }

  Future<void> _ensureFullGuide({required bool force}) async {
    _guideRefreshing = true;
    _guideStatus = '';
    notifyListeners();
    try {
      final urls = await client.epgGuideUrls();
      if (urls.isEmpty) {
        _guideStatus = 'No guide source was provided.';
        return;
      }
      var refreshed = false;
      var attempted = false;
      EpgSyncException? lastFailure;
      for (final uri in urls.take(3)) {
        final source = await store.epgSourceState(
          profileScope,
          epgSourceKey(uri),
        );
        final stale =
            source == null ||
            _clock().toUtc().difference(source.fetchedAt) >= xmltvFreshness;
        if (!force && !stale) continue;
        attempted = true;
        try {
          await client.syncEpgGuide(uri, store: store, now: _clock().toUtc());
          refreshed = true;
        } on EpgSyncException catch (error) {
          lastFailure = error;
        }
      }
      _guideStatus = refreshed
          ? 'Guide updated'
          : attempted
          ? lastFailure?.message ?? 'The guide could not be refreshed.'
          : 'Guide is up to date';
    } on EpgSyncException catch (error) {
      _guideStatus = error.message;
    } catch (_) {
      _guideStatus = 'The guide could not be refreshed.';
    } finally {
      _guideRefreshing = false;
      if (!_disposed) notifyListeners();
    }
  }

  /// Read a time window for the requested channels from every cached source.
  /// Exact, unambiguous channel matching prevents unrelated schedules from
  /// being shown under similarly named channels.
  Future<Map<int, List<EpgProgramme>>> guideWindow(
    List<LiveStream> channels, {
    required DateTime startUtc,
    required DateTime endUtc,
  }) async {
    final output = <int, List<EpgProgramme>>{
      for (final channel in channels)
        channel.streamId: <EpgProgramme>[...?_programmes[channel.streamId]],
    };
    final urls = await client.epgGuideUrls();
    for (final uri in urls.take(3)) {
      final sourceKey = epgSourceKey(uri);
      final guideChannels = await store.epgChannels(profileScope, sourceKey);
      final mapping = matchEpgChannels(channels, guideChannels);
      if (mapping.isEmpty) continue;
      final programmes = await store.epgWindow(
        profileScope,
        sourceKey,
        channelKeys: mapping.values.toSet().toList(growable: false),
        startUtc: startUtc,
        endUtc: endUtc,
      );
      final reverse = <String, List<int>>{};
      for (final entry in mapping.entries) {
        (reverse[entry.value] ??= <int>[]).add(entry.key);
      }
      for (final programme in programmes) {
        for (final streamId in reverse[programme.channelKey] ?? const <int>[]) {
          (output[streamId] ??= <EpgProgramme>[]).add(programme);
        }
      }
    }
    for (final values in output.values) {
      values.sort((a, b) => a.startUtc.compareTo(b.startUtc));
      final seen = <String>{};
      values.removeWhere(
        (programme) => !seen.add(
          '${programme.startUtc.millisecondsSinceEpoch}:${programme.title}',
        ),
      );
    }
    return output;
  }

  @override
  void dispose() {
    _disposed = true;
    _queue.clear();
    super.dispose();
  }
}

/// Deterministic channel mapper: identifier first, then unique exact names.
Map<int, String> matchEpgChannels(
  Iterable<LiveStream> liveChannels,
  Iterable<EpgChannel> guideChannels,
) {
  final guides = guideChannels.toList(growable: false);
  final ids = <String, EpgChannel>{
    for (final guide in guides) guide.channelKey.trim().toLowerCase(): guide,
  };
  final names = <String, List<EpgChannel>>{};
  for (final guide in guides) {
    for (final raw in guide.displayNames) {
      final normalized = normalizeChannelName(raw);
      if (normalized.isNotEmpty) {
        (names[normalized] ??= <EpgChannel>[]).add(guide);
      }
    }
  }

  final result = <int, String>{};
  for (final channel in liveChannels) {
    final epgId = channel.epgId.trim().toLowerCase();
    final idMatch = epgId.isEmpty ? null : ids[epgId];
    if (idMatch != null) {
      result[channel.streamId] = idMatch.channelKey;
      continue;
    }
    for (final raw in [channel.epgName, channel.name]) {
      final normalized = normalizeChannelName(raw);
      final candidates = names[normalized] ?? const <EpgChannel>[];
      final uniqueKeys = candidates.map((item) => item.channelKey).toSet();
      if (uniqueKeys.length == 1) {
        result[channel.streamId] = uniqueKeys.single;
        break;
      }
    }
  }
  return result;
}
