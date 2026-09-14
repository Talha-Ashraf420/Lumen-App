import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../epg_repository.dart';
import '../library.dart';
import '../models.dart';
import '../playback.dart';
import '../theme.dart';
import '../widgets.dart';
import '../xtream.dart';

enum LiveHubSection { channels, recent, favourites }

typedef LiveHubSelection = void Function(PlayerItem item, int? playlistIndex);

String _liveHubItemKey(PlayerItem item) =>
    item.favRef?.key ?? '${item.url}\n${item.title}';

/// Builds a stable, duplicate-free list for an in-player Live Hub section.
/// Kept outside the widget so list ordering can be regression-tested without a
/// player or provider connection.
List<PlayerItem> liveHubItemsFor({
  required LiveHubSection section,
  required List<PlayerItem> playlist,
  required Iterable<MediaRef> recent,
  required Iterable<MediaRef> favourites,
  required PlayerItem Function(MediaRef ref) fromRef,
}) {
  final source = switch (section) {
    LiveHubSection.channels => playlist.where((item) => item.isLive),
    LiveHubSection.recent =>
      recent.where((ref) => ref.isLive && ref.url.isNotEmpty).map(fromRef),
    LiveHubSection.favourites =>
      favourites.where((ref) => ref.isLive && ref.url.isNotEmpty).map(fromRef),
  };
  final seen = <String>{};
  return [
    for (final item in source)
      if (seen.add(_liveHubItemKey(item))) item,
  ];
}

class LiveControlHub extends StatefulWidget {
  const LiveControlHub({
    super.key,
    required this.controller,
    required this.onSelect,
    required this.onClose,
    this.client,
  });

  final PlaybackController controller;
  final XtreamClient? client;
  final LiveHubSelection onSelect;
  final VoidCallback onClose;

  @override
  State<LiveControlHub> createState() => _LiveControlHubState();
}

class _LiveControlHubState extends State<LiveControlHub> {
  LiveHubSection _section = LiveHubSection.channels;
  EpgRepository? _epg;
  final Set<int> _primed = <int>{};

  Color get _accent => ThemeController.instance.accent.value;

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_refresh);
    Library.instance.addListener(_refresh);
    final client = widget.client;
    if (client != null) {
      _epg = EpgRepository(client: client)..addListener(_refresh);
    }
    WidgetsBinding.instance.addPostFrameCallback((_) => _primeVisible());
  }

  @override
  void dispose() {
    widget.controller.removeListener(_refresh);
    Library.instance.removeListener(_refresh);
    _epg?.removeListener(_refresh);
    _epg?.dispose();
    super.dispose();
  }

  void _refresh() {
    if (mounted) setState(() {});
  }

  PlayerItem _fromRef(MediaRef ref) => PlayerItem(
    ref.url,
    ref.name,
    isLive: true,
    poster: ref.image,
    httpHeaders: widget.client?.streamHeaders(ref.id) ?? const {},
    favRef: ref,
  );

  List<PlayerItem> get _items => liveHubItemsFor(
    section: _section,
    playlist: widget.controller.items,
    recent: Library.instance.recent,
    favourites: Library.instance.favourites,
    fromRef: _fromRef,
  );

  int? _playlistIndex(PlayerItem item) {
    final key = _liveHubItemKey(item);
    final index = widget.controller.items.indexWhere(
      (candidate) => _liveHubItemKey(candidate) == key,
    );
    return index < 0 ? null : index;
  }

  LiveStream? _channelFor(PlayerItem item) {
    final ref = item.favRef;
    if (ref == null || !ref.isLive || ref.id <= 0) return null;
    return LiveStream(ref.id, ref.name, ref.image, ref.cat);
  }

  void _primeVisible() {
    final repository = _epg;
    if (!mounted || repository == null) return;
    final channels = <LiveStream>[];
    for (final item in _items.take(10)) {
      final channel = _channelFor(item);
      if (channel != null && _primed.add(channel.streamId)) {
        channels.add(channel);
      }
    }
    final current = widget.controller.currentItem;
    if (current != null) {
      final channel = _channelFor(current);
      if (channel != null && _primed.add(channel.streamId)) {
        channels.insert(0, channel);
      }
    }
    if (channels.isNotEmpty) unawaited(repository.primeVisible(channels));
  }

  void _selectSection(LiveHubSection section) {
    if (_section == section) return;
    setState(() => _section = section);
    WidgetsBinding.instance.addPostFrameCallback((_) => _primeVisible());
  }

  @override
  Widget build(BuildContext context) {
    final items = _items;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(18, 14, 10, 8),
          child: Row(
            children: [
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  color: _accent.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(lumenCorner(11)),
                ),
                child: Icon(Icons.live_tv_rounded, color: _accent, size: 20),
              ),
              const SizedBox(width: 11),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Live control hub',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    Text(
                      'Switch without leaving the stream',
                      style: TextStyle(color: Colors.white54, fontSize: 11.5),
                    ),
                  ],
                ),
              ),
              IconButton(
                autofocus: true,
                tooltip: 'Close live control hub',
                onPressed: widget.onClose,
                icon: const Icon(Icons.close_rounded),
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(14, 4, 14, 10),
          child: Row(
            children: [
              Expanded(
                child: _sectionButton(LiveHubSection.channels, 'Channels'),
              ),
              const SizedBox(width: 6),
              Expanded(child: _sectionButton(LiveHubSection.recent, 'Recent')),
              const SizedBox(width: 6),
              Expanded(
                child: _sectionButton(LiveHubSection.favourites, 'My list'),
              ),
            ],
          ),
        ),
        const Divider(color: Colors.white12, height: 1),
        Expanded(
          child: items.isEmpty
              ? _emptyState()
              : ListView.separated(
                  padding: const EdgeInsets.fromLTRB(10, 10, 10, 24),
                  itemCount: items.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 4),
                  itemBuilder: (context, index) => _channelRow(items[index]),
                ),
        ),
      ],
    );
  }

  Widget _sectionButton(LiveHubSection section, String label) {
    final selected = _section == section;
    return RemoteTap(
      semanticLabel: '$label live channels',
      onTap: () => _selectSection(section),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        height: 38,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: selected ? _accent : Colors.white.withValues(alpha: 0.07),
          borderRadius: BorderRadius.circular(lumenCorner(12)),
          border: Border.all(
            color: selected ? _accent : Colors.white.withValues(alpha: 0.12),
          ),
        ),
        child: Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            color: selected ? foregroundFor(_accent) : Colors.white70,
            fontSize: 12,
            fontWeight: FontWeight.w800,
          ),
        ),
      ),
    );
  }

  Widget _channelRow(PlayerItem item) {
    final playlistIndex = _playlistIndex(item);
    final active = playlistIndex == widget.controller.index;
    final ref = item.favRef;
    final guide = ref == null ? null : _epg?.nowNextFor(ref.id);
    final now = guide?.now?.title.trim() ?? '';
    final next = guide?.next?.title.trim() ?? '';

    return RemoteTap(
      semanticLabel: active ? '${item.title}, playing' : 'Play ${item.title}',
      onTap: () => widget.onSelect(item, playlistIndex),
      child: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: active
              ? _accent.withValues(alpha: 0.16)
              : Colors.white.withValues(alpha: 0.045),
          borderRadius: BorderRadius.circular(lumenCorner(13)),
          border: Border.all(
            color: active
                ? _accent.withValues(alpha: 0.75)
                : Colors.white.withValues(alpha: 0.08),
          ),
        ),
        child: Row(
          children: [
            _channelArt(item),
            const SizedBox(width: 11),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      if (active) ...[
                        Icon(
                          Icons.graphic_eq_rounded,
                          color: _accent,
                          size: 15,
                        ),
                        const SizedBox(width: 5),
                      ],
                      Expanded(
                        child: Text(
                          item.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 13.5,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 3),
                  if (now.isNotEmpty)
                    Text(
                      'Now  $now',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white70,
                        fontSize: 11.5,
                      ),
                    )
                  else
                    const Text(
                      'Live now',
                      style: TextStyle(color: Colors.white38, fontSize: 11.5),
                    ),
                  if (next.isNotEmpty)
                    Text(
                      'Next  $next',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white38,
                        fontSize: 10.5,
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            if (ref != null && Library.instance.isFav(ref.key))
              Icon(Icons.favorite_rounded, color: _accent, size: 16),
            const SizedBox(width: 7),
            Icon(
              active ? Icons.volume_up_rounded : Icons.play_arrow_rounded,
              color: active ? _accent : Colors.white54,
              size: 20,
            ),
          ],
        ),
      ),
    );
  }

  Widget _channelArt(PlayerItem item) {
    final image = item.favRef?.image.isNotEmpty == true
        ? item.favRef!.image
        : item.poster;
    final fallback = Container(
      color: Colors.white.withValues(alpha: 0.07),
      alignment: Alignment.center,
      child: const Icon(Icons.live_tv_rounded, color: Colors.white38, size: 19),
    );
    return ClipRRect(
      borderRadius: BorderRadius.circular(lumenCorner(10)),
      child: SizedBox(
        width: 48,
        height: 48,
        child: image.isEmpty
            ? fallback
            : CachedNetworkImage(
                imageUrl: image,
                fit: BoxFit.contain,
                placeholder: (_, _) => fallback,
                errorWidget: (_, _, _) => fallback,
              ),
      ),
    );
  }

  Widget _emptyState() => Center(
    child: Padding(
      padding: const EdgeInsets.all(28),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.live_tv_outlined, color: Colors.white30, size: 38),
          const SizedBox(height: 10),
          Text(
            switch (_section) {
              LiveHubSection.channels => 'No other channels in this list.',
              LiveHubSection.recent => 'Recently played channels appear here.',
              LiveHubSection.favourites => 'Save channels to find them here.',
            },
            textAlign: TextAlign.center,
            style: const TextStyle(color: Colors.white54, height: 1.4),
          ),
        ],
      ),
    ),
  );
}
