import 'dart:async';
import 'dart:collection';

import 'package:flutter/foundation.dart';

import 'catalog_store.dart';
import 'channel_logos.dart';
import 'epg.dart';
import 'epg_loader.dart';
import 'epg_settings.dart';
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
       profileScope = Store.profileScope(client.creds) {
    epgConfigurationRevision.addListener(_onConfigurationChanged);
  }

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
  Future<void>? _settingsLoad;
  EpgSettings? _settings;
  Duration _guideOffset = Duration.zero;
  int _visibleRevision = 0;
  bool _disposed = false;
  bool _guideRefreshing = false;
  String _guideStatus = '';

  bool get guideRefreshing => _guideRefreshing;
  String get guideStatus => _guideStatus;
  int get shortRequestsInFlight => _loading.length;

  bool isLoading(int streamId) => _loading.contains(streamId);

  Future<void> _ensureSettings() =>
      _settingsLoad ??= EpgSettings.load(client.creds).then((settings) {
        _settings = settings;
        _guideOffset = Duration(minutes: settings.offsetMinutes);
      });

  Future<List<Uri>> _guideUrls() async {
    await _ensureSettings();
    final settings = _settings ?? const EpgSettings();
    final values = <Uri>[
      if (settings.manualUrl.isNotEmpty) Uri.parse(settings.manualUrl),
      ...await client.epgGuideUrls(),
    ];
    final seen = <String>{};
    return [
      for (final value in values)
        if (seen.add('$value')) value,
    ];
  }

  EpgProgramme _shiftProgramme(EpgProgramme value) {
    if (_guideOffset == Duration.zero) return value;
    return value.copyWith(
      startUtc: value.startUtc.add(_guideOffset),
      stopUtc: value.stopUtc.add(_guideOffset),
    );
  }

  EpgNowNext nowNextFor(int streamId, {DateTime? at}) {
    final time = (at ?? _clock()).toUtc().subtract(_guideOffset);
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
    return EpgNowNext(
      now: current == null ? null : _shiftProgramme(current),
      next: next == null ? null : _shiftProgramme(next),
    );
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

    await _ensureSettings();

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
    final shortEpgChannels = channels
        .where((channel) => client.supportsShortEpg(channel.streamId))
        .toList(growable: false);
    if (shortEpgChannels.isEmpty) {
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
    for (final channel in shortEpgChannels) {
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
      // Loading is invisible on channel tiles; rebuilding the whole grid for
      // each queued request adds work without presenting new programme data.
      unawaited(_fetchShort(channel));
    }
  }

  Future<void> _fetchShort(LiveStream channel) async {
    final fetchedAt = _clock().toUtc();
    var programmesChanged = false;
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
      programmesChanged = true;
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
        if (programmesChanged) notifyListeners();
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
      final urls = await _guideUrls();
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
          await client.syncEpgGuide(
            uri,
            store: store,
            now: _clock().toUtc(),
            profileScope: profileScope,
          );
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
    await _ensureSettings();
    final output = <int, List<EpgProgramme>>{
      for (final channel in channels)
        channel.streamId: <EpgProgramme>[...?_programmes[channel.streamId]],
    };
    final urls = await _guideUrls();
    final rawStartUtc = startUtc.subtract(_guideOffset);
    final rawEndUtc = endUtc.subtract(_guideOffset);
    final manualMappings = await store.epgChannelMappings(profileScope);
    final manuallyOwnedIds = manualMappings
        .map((mapping) => mapping.liveStreamId)
        .toSet();
    for (final uri in urls.take(3)) {
      final sourceKey = epgSourceKey(uri);
      final guideChannels = await store.epgChannels(profileScope, sourceKey);
      final mapping = matchEpgChannels(channels, guideChannels);
      mapping.removeWhere((streamId, _) => manuallyOwnedIds.contains(streamId));
      final availableKeys = guideChannels
          .map((channel) => channel.channelKey)
          .toSet();
      for (final manual in manualMappings) {
        if (manual.sourceKey == sourceKey &&
            availableKeys.contains(manual.epgChannelKey)) {
          mapping[manual.liveStreamId] = manual.epgChannelKey;
        }
      }
      if (mapping.isEmpty) continue;
      final programmes = await store.epgWindow(
        profileScope,
        sourceKey,
        channelKeys: mapping.values.toSet().toList(growable: false),
        startUtc: rawStartUtc,
        endUtc: rawEndUtc,
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
      if (_guideOffset != Duration.zero) {
        for (var index = 0; index < values.length; index++) {
          values[index] = _shiftProgramme(values[index]);
        }
      }
    }
    return output;
  }

  Future<EpgCacheDiagnostics> diagnostics() =>
      EpgCacheDiagnostics.load(client.creds, store: store);

  Future<List<EpgChannelMapping>> manualMappings() =>
      store.epgChannelMappings(profileScope);

  Future<void> setManualMapping({
    required int liveStreamId,
    required String sourceKey,
    required String epgChannelKey,
  }) async {
    await store.setManualEpgChannelMapping(
      profileScope,
      liveStreamId: liveStreamId,
      sourceKey: sourceKey,
      epgChannelKey: epgChannelKey,
    );
    notifyEpgConfigurationChanged();
  }

  Future<void> clearManualMapping(int liveStreamId) async {
    await store.clearManualEpgChannelMapping(profileScope, liveStreamId);
    notifyEpgConfigurationChanged();
  }

  Future<void> clearCache() async {
    await store.clearEpgProfile(profileScope);
    notifyEpgConfigurationChanged();
  }

  void _onConfigurationChanged() {
    _settingsLoad = null;
    _settings = null;
    _guideOffset = Duration.zero;
    _guideStatus = '';
    _programmes.clear();
    _freshUntil.clear();
    _queue.clear();
    _queued.clear();
    _visibleRevision++;
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    epgConfigurationRevision.removeListener(_onConfigurationChanged);
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
