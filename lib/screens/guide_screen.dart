import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import '../epg_cache.dart';
import '../library.dart';
import '../models.dart';
import '../theme.dart';
import '../widgets.dart';
import '../xtream.dart';
import 'category_sheet.dart';
import 'player_screen.dart';

/// The "Live" tab — a TV guide: channel rows with now/next + progress, a category
/// filter, tap-to-play (with channel zapping), and a full-day schedule sheet that
/// offers catch-up for archived programmes.
class GuideScreen extends StatefulWidget {
  final XtreamClient client;
  const GuideScreen({super.key, required this.client});
  @override
  State<GuideScreen> createState() => _GuideScreenState();
}

class _GuideScreenState extends State<GuideScreen> with AutomaticKeepAliveClientMixin {
  List<Category> _cats = [];
  String? _cat;
  late Future<List<LiveStream>> _channels;
  bool _ready = false;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    try {
      final cats = await widget.client.liveCategories();
      if (!mounted) return;
      setState(() {
        _cats = cats;
        _cat = cats.isNotEmpty ? cats.first.id : null;
        _ready = true;
        _channels = _load();
      });
    } catch (_) {
      if (mounted) setState(() => _ready = true);
    }
  }

  Future<List<LiveStream>> _load() => widget.client.liveStreams(_cat).catchError((_) => <LiveStream>[]);

  String get _catName =>
      _cats.firstWhere((c) => c.id == _cat, orElse: () => Category(_cat ?? 'all', 'All channels')).name;

  Future<void> _pickCategory() async {
    final r = await showCategorySheet(context, categories: _cats, selected: _cat);
    if (r != null && mounted) setState(() {
      _cat = r;
      _channels = _load();
    });
  }

  PlayerItem _liveItem(LiveStream s) {
    final url = widget.client.streamUrl('live', s.streamId, ext: 'ts');
    return PlayerItem(url, s.name,
        isLive: true,
        poster: s.icon,
        favRef: MediaRef(kind: 'live', id: s.streamId, name: s.name, image: s.icon, url: url),
        epg: () => EpgCache.instance.nowNext(widget.client, s.streamId));
  }

  void _play(List<LiveStream> all, int index) {
    final pl = all.map(_liveItem).toList();
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => PlayerScreen(items: pl, index: index)));
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    if (!_ready) return const BrandedLoading();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Padding(
          padding: EdgeInsets.fromLTRB(20, 6, 20, 10),
          child: Text('Live TV', style: TextStyle(fontSize: 26, fontWeight: FontWeight.w800)),
        ),
        if (_cats.isNotEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: GestureDetector(
              onTap: _pickCategory,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                decoration: BoxDecoration(
                  color: surfaceHi.withValues(alpha: 0.7),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: line),
                ),
                child: Row(children: [
                  Icon(Icons.grid_view_rounded, size: 18, color: accent),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(_catName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontWeight: FontWeight.w700)),
                  ),
                  Icon(Icons.keyboard_arrow_down_rounded, color: muted),
                ]),
              ),
            ),
          ),
        Expanded(
          child: FutureBuilder<List<LiveStream>>(
            future: _channels,
            builder: (context, snap) {
              if (snap.connectionState != ConnectionState.done) {
                return Center(child: CircularProgressIndicator(color: accent, strokeWidth: 2));
              }
              final chans = snap.data ?? [];
              if (chans.isEmpty) return Center(child: Text('No channels here.', style: TextStyle(color: subtle)));
              return ListView.separated(
                padding: const EdgeInsets.fromLTRB(12, 4, 12, 120),
                itemCount: chans.length,
                separatorBuilder: (_, _) => const SizedBox(height: 6),
                itemBuilder: (_, i) => _ChannelRow(
                  client: widget.client,
                  channel: chans[i],
                  onTap: () => _play(chans, i),
                  onSchedule: () => _showSchedule(chans[i]),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  // ---- full-day schedule + catch-up ----
  void _showSchedule(LiveStream channel) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => _ScheduleSheet(
        client: widget.client,
        channel: channel,
        onWatch: (entry) {
          Navigator.pop(context);
          final url = widget.client.timeshiftUrl(channel.streamId, entry.timeshiftStart, entry.durationMinutes);
          Navigator.of(context).push(MaterialPageRoute(
            builder: (_) => PlayerScreen(items: [
              PlayerItem(url, '${channel.name} · ${entry.title}', ext: 'ts', poster: channel.icon),
            ]),
          ));
        },
      ),
    );
  }
}

/// One channel row: logo, name, now/next + progress, schedule button.
class _ChannelRow extends StatelessWidget {
  final XtreamClient client;
  final LiveStream channel;
  final VoidCallback onTap;
  final VoidCallback onSchedule;
  const _ChannelRow({required this.client, required this.channel, required this.onTap, required this.onSchedule});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: Container(
                width: 54,
                height: 54,
                color: surfaceHi,
                padding: const EdgeInsets.all(6),
                child: channel.icon.isNotEmpty
                    ? CachedNetworkImage(
                        imageUrl: channel.icon,
                        fit: BoxFit.contain,
                        errorWidget: (_, _, _) => Icon(Icons.live_tv_rounded, color: subtle, size: 24),
                      )
                    : Icon(Icons.live_tv_rounded, color: subtle, size: 24),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(channel.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14.5)),
                      ),
                      if (channel.hasArchive)
                        Padding(
                          padding: const EdgeInsets.only(left: 6),
                          child: Icon(Icons.history_rounded, size: 15, color: subtle),
                        ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  FutureBuilder<List<EpgEntry>>(
                    future: EpgCache.instance.nowNext(client, channel.streamId),
                    builder: (_, snap) {
                      final list = snap.data ?? const [];
                      if (list.isEmpty) {
                        return Text(
                          snap.connectionState == ConnectionState.done ? 'No guide data' : '…',
                          style: TextStyle(color: subtle, fontSize: 12),
                        );
                      }
                      final now = list.firstWhere((e) => e.isNow, orElse: () => list.first);
                      final ni = list.indexOf(now);
                      final next = ni + 1 < list.length ? list[ni + 1] : null;
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Now · ${now.title}',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(color: muted, fontSize: 12.5, fontWeight: FontWeight.w600)),
                          const SizedBox(height: 4),
                          ClipRRect(
                            borderRadius: BorderRadius.circular(2),
                            child: LinearProgressIndicator(
                              value: now.progress.toDouble(),
                              minHeight: 3,
                              backgroundColor: surfaceHi,
                              valueColor: AlwaysStoppedAnimation(accent),
                            ),
                          ),
                          if (next != null) ...[
                            const SizedBox(height: 4),
                            Text('Next · ${next.title}',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(color: subtle, fontSize: 11.5)),
                          ],
                        ],
                      );
                    },
                  ),
                ],
              ),
            ),
            IconButton(
              onPressed: onSchedule,
              icon: Icon(Icons.calendar_month_rounded, color: muted, size: 20),
              tooltip: 'Schedule',
            ),
          ],
        ),
      ),
    );
  }
}

/// Full-day schedule for a channel with catch-up actions on archived programmes.
class _ScheduleSheet extends StatelessWidget {
  final XtreamClient client;
  final LiveStream channel;
  final void Function(EpgEntry) onWatch;
  const _ScheduleSheet({required this.client, required this.channel, required this.onWatch});

  bool _canCatchUp(EpgEntry e) {
    if (!channel.hasArchive || !e.isPast) return false;
    final daysAgo = DateTime.now().difference(e.start).inDays;
    return daysAgo <= (channel.tvArchiveDuration <= 0 ? 7 : channel.tvArchiveDuration);
  }

  String _time(DateTime d) {
    String two(int n) => n.toString().padLeft(2, '0');
    return '${two(d.hour)}:${two(d.minute)}';
  }

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.8,
      minChildSize: 0.4,
      maxChildSize: 0.95,
      builder: (context, scroll) {
        return Container(
          decoration: BoxDecoration(
            color: surface,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
            border: Border(top: BorderSide(color: line)),
          ),
          child: Column(
            children: [
              const SizedBox(height: 10),
              Container(width: 40, height: 4, decoration: BoxDecoration(color: subtle, borderRadius: BorderRadius.circular(2))),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 14, 20, 8),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(channel.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w800)),
                    ),
                    if (channel.hasArchive)
                      Row(mainAxisSize: MainAxisSize.min, children: [
                        Icon(Icons.history_rounded, size: 15, color: accent),
                        const SizedBox(width: 4),
                        Text('Catch-up', style: TextStyle(color: accent, fontSize: 12, fontWeight: FontWeight.w700)),
                      ]),
                  ],
                ),
              ),
              Expanded(
                child: FutureBuilder<List<EpgEntry>>(
                  future: EpgCache.instance.fullDay(client, channel.streamId),
                  builder: (_, snap) {
                    if (snap.connectionState != ConnectionState.done) {
                      return Center(child: CircularProgressIndicator(color: accent, strokeWidth: 2));
                    }
                    final list = snap.data ?? const [];
                    if (list.isEmpty) {
                      return Center(child: Text('No schedule available.', style: TextStyle(color: subtle)));
                    }
                    return ListView.builder(
                      controller: scroll,
                      padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
                      itemCount: list.length,
                      itemBuilder: (_, i) {
                        final e = list[i];
                        final canWatch = _canCatchUp(e);
                        return Container(
                          margin: const EdgeInsets.symmetric(vertical: 3),
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                          decoration: BoxDecoration(
                            color: e.isNow ? accent.withValues(alpha: 0.14) : surfaceHi.withValues(alpha: 0.4),
                            borderRadius: BorderRadius.circular(14),
                            border: e.isNow ? Border.all(color: accent.withValues(alpha: 0.5)) : null,
                          ),
                          child: Row(
                            children: [
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text('${_time(e.start)}–${_time(e.end)}',
                                      style: TextStyle(color: e.isNow ? accent : subtle, fontSize: 11.5, fontWeight: FontWeight.w700)),
                                ],
                              ),
                              const SizedBox(width: 14),
                              Expanded(
                                child: Text(e.title,
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                        fontWeight: e.isNow ? FontWeight.w700 : FontWeight.w500,
                                        fontSize: 13.5,
                                        color: e.isPast && !e.isNow ? muted : null)),
                              ),
                              if (e.isNow)
                                Padding(
                                  padding: const EdgeInsets.only(left: 8),
                                  child: Icon(Icons.circle, size: 9, color: accent),
                                )
                              else if (canWatch)
                                GestureDetector(
                                  onTap: () => onWatch(e),
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                                    decoration: BoxDecoration(color: accent, borderRadius: BorderRadius.circular(10)),
                                    child: const Row(mainAxisSize: MainAxisSize.min, children: [
                                      Icon(Icons.play_arrow_rounded, color: Colors.white, size: 16),
                                      SizedBox(width: 3),
                                      Text('Watch', style: TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w700)),
                                    ]),
                                  ),
                                ),
                            ],
                          ),
                        );
                      },
                    );
                  },
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
