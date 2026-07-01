import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:linked_scroll_controller/linked_scroll_controller.dart';
import '../catalog_cache.dart';
import '../epg_cache.dart';
import '../library.dart';
import '../models.dart';
import '../playback.dart';
import '../theme.dart';
import '../widgets.dart';
import '../xtream.dart';
import 'category_sheet.dart';

/// A classic TV-guide grid: a sticky channel column on the left, a time axis
/// across the top, and program blocks laid out by start/duration. Horizontal
/// and vertical scrolling are synchronised (channel column ↔ body, time axis ↔
/// body) via [LinkedScrollControllerGroup]. EPG for each channel loads lazily
/// as its row scrolls into view. A red line marks "now".
class EpgGuideScreen extends StatefulWidget {
  final XtreamClient client;
  const EpgGuideScreen({super.key, required this.client});
  @override
  State<EpgGuideScreen> createState() => _EpgGuideScreenState();
}

class _EpgGuideScreenState extends State<EpgGuideScreen> with AutomaticKeepAliveClientMixin {
  static const double _pxPerMin = 3.0;
  static const double _rowH = 66;
  static const double _headerH = 44;
  static const int _windowMinutes = 24 * 60;
  double get _totalW => _windowMinutes * _pxPerMin;

  final _hGroup = LinkedScrollControllerGroup();
  late final ScrollController _hHead = _hGroup.addAndGet();
  late final ScrollController _hBody = _hGroup.addAndGet();
  final _vGroup = LinkedScrollControllerGroup();
  late final ScrollController _vCol = _vGroup.addAndGet();
  late final ScrollController _vBody = _vGroup.addAndGet();

  late final DateTime _windowStart; // today 00:00 local
  List<Category> _cats = [];
  String? _cat;
  List<LiveStream> _channels = [];
  bool _ready = false;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    final n = DateTime.now();
    _windowStart = DateTime(n.year, n.month, n.day);
    _init();
  }

  @override
  void dispose() {
    _hHead.dispose();
    _hBody.dispose();
    _vCol.dispose();
    _vBody.dispose();
    super.dispose();
  }

  Future<void> _init() async {
    try {
      final cats = await CatalogCache.instance.live(widget.client);
      _cat = cats.isNotEmpty ? cats.first.id : null;
      final chans = await widget.client.liveStreams(_cat).catchError((_) => <LiveStream>[]);
      if (!mounted) return;
      setState(() {
        _cats = cats;
        _channels = chans;
        _ready = true;
      });
      WidgetsBinding.instance.addPostFrameCallback((_) => _jumpToNow());
    } catch (_) {
      if (mounted) setState(() => _ready = true);
    }
  }

  Future<void> _pickCategory() async {
    final r = await showCategorySheet(context, categories: _cats, selected: _cat);
    if (r == null || !mounted || r == _cat) return;
    setState(() {
      _cat = r;
      _ready = false;
    });
    final chans = await widget.client.liveStreams(_cat).catchError((_) => <LiveStream>[]);
    if (mounted) setState(() {
      _channels = chans;
      _ready = true;
    });
  }

  String get _catName =>
      _cats.firstWhere((c) => c.id == _cat, orElse: () => Category(_cat ?? 'all', 'All channels')).name;

  double get _nowX {
    final mins = DateTime.now().difference(_windowStart).inMinutes.clamp(0, _windowMinutes);
    return mins * _pxPerMin;
  }

  void _jumpToNow() {
    if (!_hBody.hasClients) return;
    final target = (_nowX - 140).clamp(0.0, _hBody.position.maxScrollExtent);
    _hBody.jumpTo(target);
  }

  PlayerItem _liveItem(LiveStream s) {
    final url = widget.client.streamUrl('live', s.streamId, ext: 'ts');
    return PlayerItem(url, s.name,
        isLive: true,
        poster: s.icon,
        favRef: MediaRef(kind: 'live', id: s.streamId, name: s.name, image: s.icon, url: url),
        epg: () => EpgCache.instance.nowNext(widget.client, s.streamId));
  }

  void _playLive(int index) {
    PlaybackController.instance.open(_channels.map(_liveItem).toList(), index);
  }

  bool _canCatchUp(LiveStream c, EpgEntry e) {
    if (!c.hasArchive || !e.isPast) return false;
    final daysAgo = DateTime.now().difference(e.start).inDays;
    return daysAgo <= (c.tvArchiveDuration <= 0 ? 7 : c.tvArchiveDuration);
  }

  String _hhmm(DateTime d) {
    String two(int n) => n.toString().padLeft(2, '0');
    return '${two(d.hour)}:${two(d.minute)}';
  }

  void _onTapProgram(LiveStream c, int chIndex, EpgEntry e) {
    if (e.isNow) {
      _playLive(chIndex);
      return;
    }
    if (e.isPast) {
      if (_canCatchUp(c, e)) {
        final url = widget.client.timeshiftUrl(c.streamId, e.timeshiftStart, e.durationMinutes);
        PlaybackController.instance.open([PlayerItem(url, '${c.name} · ${e.title}', ext: 'ts', poster: c.icon)], 0);
      } else {
        _toast('Not available for catch-up');
      }
      return;
    }
    _toast('“${e.title}” starts at ${_hhmm(e.start)}');
  }

  void _toast(String m) => ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(m), duration: const Duration(seconds: 2)));

  @override
  Widget build(BuildContext context) {
    super.build(context);
    if (!_ready) return BrandedLoading();
    final colW = MediaQuery.sizeOf(context).width >= 900 ? 156.0 : 110.0;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _topBar(),
        Expanded(
          child: _channels.isEmpty
              ? Center(child: Text('No channels here.', style: TextStyle(color: subtle)))
              : Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // sticky channel column
                    SizedBox(
                      width: colW,
                      child: Column(
                        children: [
                          Container(
                            height: _headerH,
                            alignment: Alignment.centerLeft,
                            padding: const EdgeInsets.only(left: 16),
                            decoration: BoxDecoration(border: Border(bottom: BorderSide(color: line), right: BorderSide(color: line))),
                            child: Text('CHANNELS', style: kSection()),
                          ),
                          Expanded(
                            child: ListView.builder(
                              controller: _vCol,
                              itemCount: _channels.length,
                              itemBuilder: (_, i) => _channelTile(_channels[i], i),
                            ),
                          ),
                        ],
                      ),
                    ),
                    // time axis + program grid
                    Expanded(
                      child: Column(
                        children: [
                          SizedBox(
                            height: _headerH,
                            child: SingleChildScrollView(
                              controller: _hHead,
                              scrollDirection: Axis.horizontal,
                              physics: const NeverScrollableScrollPhysics(),
                              child: _timeAxis(),
                            ),
                          ),
                          Expanded(
                            child: SingleChildScrollView(
                              controller: _hBody,
                              scrollDirection: Axis.horizontal,
                              child: SizedBox(
                                width: _totalW,
                                child: Stack(
                                  children: [
                                    ListView.builder(
                                      controller: _vBody,
                                      itemCount: _channels.length,
                                      itemBuilder: (_, i) => _row(_channels[i], i),
                                    ),
                                    // "now" marker
                                    Positioned(
                                      left: _nowX,
                                      top: 0,
                                      bottom: 0,
                                      child: Container(width: 2, color: const Color(0xFFFF3B5C)),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
        ),
      ],
    );
  }

  Widget _topBar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 8, 12, 10),
      child: Row(
        children: [
          const Text('TV Guide', style: TextStyle(fontSize: 28, fontWeight: FontWeight.w800, letterSpacing: -0.5)),
          const SizedBox(width: 12),
          Icon(Icons.grid_view_rounded, color: accent, size: 22),
          const Spacer(),
          if (_cats.isNotEmpty)
            GestureDetector(
              onTap: _pickCategory,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
                decoration: BoxDecoration(color: surfaceHi.withValues(alpha: 0.6), borderRadius: BorderRadius.circular(12), border: Border.all(color: line)),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  Icon(Icons.category_rounded, size: 16, color: accent),
                  const SizedBox(width: 8),
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 200),
                    child: Text(_catName, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
                  ),
                  Icon(Icons.expand_more_rounded, color: muted, size: 18),
                ]),
              ),
            ),
          const SizedBox(width: 8),
          GestureDetector(
            onTap: _jumpToNow,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
              decoration: BoxDecoration(color: accent, borderRadius: BorderRadius.circular(12)),
              child: const Row(mainAxisSize: MainAxisSize.min, children: [
                Icon(Icons.schedule_rounded, size: 16, color: Colors.white),
                SizedBox(width: 6),
                Text('Now', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 13)),
              ]),
            ),
          ),
        ],
      ),
    );
  }

  Widget _timeAxis() {
    final slots = _windowMinutes ~/ 30;
    return SizedBox(
      width: _totalW,
      height: _headerH,
      child: Stack(
        children: [
          for (int i = 0; i <= slots; i++)
            Positioned(
              left: i * 30 * _pxPerMin,
              top: 0,
              bottom: 0,
              child: Padding(
                padding: const EdgeInsets.only(left: 6),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    _hhmm(_windowStart.add(Duration(minutes: i * 30))),
                    style: TextStyle(color: i.isEven ? muted : subtle, fontSize: 11.5, fontWeight: FontWeight.w700),
                  ),
                ),
              ),
            ),
          Positioned(left: 0, right: 0, bottom: 0, child: Divider(height: 1, color: line)),
        ],
      ),
    );
  }

  Widget _channelTile(LiveStream c, int i) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => _playLive(i),
      child: Container(
        height: _rowH,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        decoration: BoxDecoration(border: Border(bottom: BorderSide(color: line), right: BorderSide(color: line))),
        child: Row(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: Container(
                width: 40,
                height: 40,
                color: surfaceHi,
                padding: const EdgeInsets.all(4),
                child: c.icon.isNotEmpty
                    ? CachedNetworkImage(imageUrl: c.icon, fit: BoxFit.contain, errorWidget: (_, _, _) => Icon(Icons.live_tv_rounded, color: subtle, size: 20))
                    : Icon(Icons.live_tv_rounded, color: subtle, size: 20),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(c.name, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 12.5, height: 1.15)),
            ),
          ],
        ),
      ),
    );
  }

  /// Some providers return overlapping or duplicate EPG entries, which would
  /// stack program blocks on top of each other. Sort by start and keep a clean
  /// non-overlapping sequence (drop zero-length and any entry that overlaps the
  /// one already kept).
  List<EpgEntry> _clean(List<EpgEntry> list) {
    final sorted = [...list]..sort((a, b) => a.start.compareTo(b.start));
    final out = <EpgEntry>[];
    DateTime? lastEnd;
    for (final e in sorted) {
      if (e.end.difference(e.start).inMinutes <= 0) continue;
      if (lastEnd != null && e.start.isBefore(lastEnd)) continue;
      out.add(e);
      lastEnd = e.end;
    }
    return out;
  }

  Widget _row(LiveStream c, int chIndex) {
    return SizedBox(
      width: _totalW,
      height: _rowH,
      child: FutureBuilder<List<EpgEntry>>(
        future: EpgCache.instance.fullDay(widget.client, c.streamId),
        builder: (_, snap) {
          final list = _clean(snap.data ?? const <EpgEntry>[]);
          return Stack(
            children: [
              Positioned(left: 0, right: 0, bottom: 0, child: Divider(height: 1, color: line)),
              if (list.isEmpty && snap.connectionState == ConnectionState.done)
                Positioned(left: 10, top: 0, bottom: 0, child: Center(child: Text('No guide data', style: TextStyle(color: subtle, fontSize: 12))))
              else
                for (final e in list) ..._maybeBlock(c, chIndex, e),
            ],
          );
        },
      ),
    );
  }

  List<Widget> _maybeBlock(LiveStream c, int chIndex, EpgEntry e) {
    final startMin = e.start.difference(_windowStart).inMinutes;
    final endMin = e.end.difference(_windowStart).inMinutes;
    if (endMin <= 0 || startMin >= _windowMinutes) return const [];
    final l = startMin.clamp(0, _windowMinutes) * _pxPerMin;
    final r = endMin.clamp(0, _windowMinutes) * _pxPerMin;
    final w = (r - l).clamp(2.0, _totalW);
    return [
      Positioned(
        left: l,
        top: 4,
        bottom: 5,
        width: w > 3 ? w - 3 : w,
        child: GestureDetector(
          onTap: () => _onTapProgram(c, chIndex, e),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
            decoration: BoxDecoration(
              color: e.isNow ? accent.withValues(alpha: 0.18) : surfaceHi.withValues(alpha: 0.45),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: e.isNow ? accent.withValues(alpha: 0.7) : line),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(e.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 12,
                        color: e.isPast && !e.isNow ? muted : textHi)),
                const SizedBox(height: 2),
                Row(
                  children: [
                    Text(_hhmm(e.start), style: TextStyle(color: e.isNow ? accent : subtle, fontSize: 10.5, fontWeight: FontWeight.w600)),
                    if (_canCatchUp(c, e)) ...[
                      const SizedBox(width: 5),
                      Icon(Icons.history_rounded, size: 11, color: subtle),
                    ],
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    ];
  }
}
