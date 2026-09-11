import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:two_dimensional_scrollables/two_dimensional_scrollables.dart';

import '../device_profile.dart';
import '../epg.dart';
import '../epg_repository.dart';
import '../library.dart';
import '../models.dart';
import '../playback.dart';
import '../responsive.dart';
import '../theme.dart';
import '../widgets.dart';
import '../xtream.dart';

// Five-minute placement cells keep real-world EPG boundaries (08:15, 08:50,
// etc.) from being rounded into the same large 30-minute cell. The table is
// virtualised, so the finer timeline does not build off-screen columns.
const Duration _guideSlot = Duration(minutes: 5);

int closestProgrammeIndexByTime(
  List<EpgProgramme> programmes,
  DateTime anchorUtc,
) {
  if (programmes.isEmpty) return -1;
  var best = 0;
  var bestDistance = 1 << 62;
  for (var index = 0; index < programmes.length; index++) {
    final programme = programmes[index];
    if (!programme.startUtc.isAfter(anchorUtc) &&
        programme.stopUtc.isAfter(anchorUtc)) {
      return index;
    }
    final midpoint = programme.startUtc.add(
      Duration(milliseconds: programme.duration.inMilliseconds ~/ 2),
    );
    final distance =
        (midpoint.millisecondsSinceEpoch - anchorUtc.millisecondsSinceEpoch)
            .abs();
    if (distance < bestDistance) {
      best = index;
      bestDistance = distance;
    }
  }
  return best;
}

class EpgGuideScreen extends StatefulWidget {
  const EpgGuideScreen({
    super.key,
    required this.client,
    required this.repository,
    required this.channels,
    this.title = 'TV Guide',
    this.initialGuide = const {},
    this.showBackButton = true,
    this.embedded = false,
    this.externalLeftFocusNode,
  });

  final XtreamClient client;
  final EpgRepository repository;
  final List<LiveStream> channels;
  final String title;
  final Map<int, List<EpgProgramme>> initialGuide;
  final bool showBackButton;
  final bool embedded;
  final FocusNode? externalLeftFocusNode;

  @override
  State<EpgGuideScreen> createState() => _EpgGuideScreenState();
}

class _EpgGuideScreenState extends State<EpgGuideScreen> {
  final ScrollController _vertical = ScrollController();
  final ScrollController _horizontal = ScrollController();
  final FocusNode _backFocus = FocusNode(debugLabel: 'Guide back');
  final FocusNode _nowFocus = FocusNode(debugLabel: 'Guide now');
  final FocusNode _refreshFocus = FocusNode(debugLabel: 'Guide refresh');
  final FocusNode _emptyRefreshFocus = FocusNode(
    debugLabel: 'Guide empty refresh',
  );
  final Map<int, FocusNode> _channelFocus = <int, FocusNode>{};
  final Map<String, FocusNode> _programmeFocus = <String, FocusNode>{};
  final Map<String, TableViewCell> _programmeCells = <String, TableViewCell>{};
  final Map<(int, int), _PlacedProgramme> _slots =
      <(int, int), _PlacedProgramme>{};
  Map<int, List<EpgProgramme>> _guide = <int, List<EpgProgramme>>{};
  late DateTime _windowStart;
  late DateTime _windowEnd;
  EpgProgramme? _selected;
  LiveStream? _selectedChannel;
  Timer? _reloadDebounce;
  bool _loading = true;
  bool _positionedAtNow = false;

  bool get _isTv => DeviceProfile.isTelevision;
  double get _channelWidth => _isTv ? 250 : 190;
  double get _slotWidth => _isTv ? 23 : 18.6667;
  double get _rowHeight => _isTv ? 84 : 72;
  int get _slotCount =>
      _windowEnd.difference(_windowStart).inMinutes ~/ _guideSlot.inMinutes;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now().toUtc();
    final rounded = DateTime.utc(
      now.year,
      now.month,
      now.day,
      now.hour,
      now.minute < 30 ? 0 : 30,
    );
    _windowStart = rounded.subtract(const Duration(hours: 6));
    _windowEnd = rounded.add(const Duration(hours: 48));
    if (widget.initialGuide.isNotEmpty) {
      _guide = {
        for (final entry in widget.initialGuide.entries)
          entry.key: List.unmodifiable(entry.value),
      };
      _loading = false;
      _rebuildSlots();
      _scheduleInitialNowPosition();
    }
    widget.repository.addListener(_onRepositoryChanged);
    unawaited(_load());
  }

  @override
  void dispose() {
    widget.repository.removeListener(_onRepositoryChanged);
    _reloadDebounce?.cancel();
    _vertical.dispose();
    _horizontal.dispose();
    _backFocus.dispose();
    _nowFocus.dispose();
    _refreshFocus.dispose();
    _emptyRefreshFocus.dispose();
    for (final node in _channelFocus.values) {
      node.dispose();
    }
    for (final node in _programmeFocus.values) {
      node.dispose();
    }
    super.dispose();
  }

  void _onRepositoryChanged() {
    if (!mounted) return;
    setState(() {});
    _reloadDebounce?.cancel();
    _reloadDebounce = Timer(const Duration(milliseconds: 260), () {
      if (mounted) unawaited(_readWindow());
    });
  }

  Future<void> _load() async {
    await widget.repository.primeVisible(widget.channels.take(16));
    await _readWindow();
    unawaited(
      widget.repository.ensureFullGuide().whenComplete(() {
        if (mounted) unawaited(_readWindow());
      }),
    );
  }

  Future<void> _readWindow() async {
    try {
      final guide = await widget.repository.guideWindow(
        widget.channels,
        startUtc: _windowStart,
        endUtc: _windowEnd,
      );
      if (!mounted) return;
      setState(() {
        _guide = guide;
        _loading = false;
        _rebuildSlots();
      });
      _scheduleInitialNowPosition();
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _rebuildSlots() {
    _slots.clear();
    _programmeCells.clear();
    for (var row = 0; row < widget.channels.length; row++) {
      final programmes = List<EpgProgramme>.of(
        _guide[widget.channels[row].streamId] ?? const [],
      )..sort((a, b) => a.startUtc.compareTo(b.startUtc));
      var nextFreeSlot = 0;
      for (var index = 0; index < programmes.length; index++) {
        final programme = programmes[index];
        final rawStart = programme.startUtc.difference(_windowStart).inMinutes;
        final rawEnd = programme.stopUtc.difference(_windowStart).inMinutes;
        var start = (rawStart / _guideSlot.inMinutes).floor().clamp(
          0,
          _slotCount - 1,
        );
        var end = (rawEnd / _guideSlot.inMinutes).ceil().clamp(
          start + 1,
          _slotCount,
        );
        // Some provider feeds contain overlapping listings for one channel.
        // Never let two merged table cells occupy the same columns: preserve
        // chronological order and trim/shift only the visual allocation.
        start = math.max(start, nextFreeSlot);
        if (start >= _slotCount) continue;
        if (index + 1 < programmes.length) {
          final nextStart =
              (programmes[index + 1].startUtc
                          .difference(_windowStart)
                          .inMinutes /
                      _guideSlot.inMinutes)
                  .floor()
                  .clamp(start + 1, _slotCount);
          end = math.min(end, nextStart);
        }
        end = math.max(start + 1, end).clamp(start + 1, _slotCount);
        final placed = _PlacedProgramme(
          row: row,
          index: index,
          startColumn: start + 1,
          span: math.max(1, end - start),
          programme: programme,
        );
        for (
          var column = placed.startColumn;
          column < placed.startColumn + placed.span;
          column++
        ) {
          _slots[(row + 1, column)] = placed;
        }
        nextFreeSlot = end;
      }
    }
  }

  String _programmeKey(int row, EpgProgramme programme) =>
      '$row:${programme.startUtc.millisecondsSinceEpoch}:${programme.title}';

  FocusNode _programmeNode(int row, EpgProgramme programme) =>
      _programmeFocus.putIfAbsent(
        _programmeKey(row, programme),
        () => FocusNode(debugLabel: 'Guide programme $row ${programme.title}'),
      );

  FocusNode _channelNode(int row) => _channelFocus.putIfAbsent(
    row,
    () => FocusNode(debugLabel: 'Guide channel $row'),
  );

  MediaRef _liveRef(LiveStream channel) {
    final url = widget.client.streamUrl('live', channel.streamId, ext: 'ts');
    return MediaRef(
      kind: 'live',
      id: channel.streamId,
      name: channel.name,
      image: channel.effectiveIcon,
      url: url,
      cat: channel.categoryId,
    );
  }

  void _play(int row) {
    final playlist = [
      for (final channel in widget.channels)
        PlayerItem(
          _liveRef(channel).url,
          channel.name,
          isLive: true,
          poster: channel.effectiveIcon,
          httpHeaders: widget.client.streamHeaders(channel.streamId),
          favRef: _liveRef(channel),
        ),
    ];
    PlaybackController.instance.open(playlist, row);
  }

  DateTime _midpoint(EpgProgramme programme) => programme.startUtc.add(
    Duration(milliseconds: programme.duration.inMilliseconds ~/ 2),
  );

  KeyEventResult _programmeKeyEvent(int row, int index, KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    final key = event.logicalKey;
    final rowProgrammes = _guide[widget.channels[row].streamId] ?? const [];
    if (key == LogicalKeyboardKey.arrowLeft) {
      if (index == 0) {
        _requestChannel(row);
      } else {
        _requestProgramme(row, index - 1);
      }
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowRight) {
      if (index + 1 < rowProgrammes.length) {
        _requestProgramme(row, index + 1);
      }
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowUp ||
        key == LogicalKeyboardKey.arrowDown) {
      final targetRow = row + (key == LogicalKeyboardKey.arrowUp ? -1 : 1);
      if (targetRow < 0) {
        _nowFocus.requestFocus();
        return KeyEventResult.handled;
      }
      if (targetRow >= widget.channels.length) {
        return KeyEventResult.handled;
      }
      final target = _guide[widget.channels[targetRow].streamId] ?? const [];
      final targetIndex = closestProgrammeIndexByTime(
        target,
        _midpoint(rowProgrammes[index]),
      );
      if (targetIndex < 0) {
        _requestChannel(targetRow);
      } else {
        _requestProgramme(targetRow, targetIndex);
      }
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  KeyEventResult _channelKeyEvent(int row, KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    final key = event.logicalKey;
    if (key == LogicalKeyboardKey.arrowLeft) {
      final externalTarget = widget.externalLeftFocusNode;
      if (externalTarget != null) {
        externalTarget.requestFocus();
      } else if (widget.showBackButton) {
        Navigator.of(context).pop();
      }
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowRight) {
      final programmes = _guide[widget.channels[row].streamId] ?? const [];
      if (programmes.isNotEmpty) {
        final now = DateTime.now().toUtc();
        final target = closestProgrammeIndexByTime(programmes, now);
        _requestProgramme(row, target);
      }
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowUp) {
      if (row == 0) {
        _nowFocus.requestFocus();
      } else {
        _requestChannel(row - 1);
      }
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowDown) {
      if (row + 1 < widget.channels.length) _requestChannel(row + 1);
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  void _requestChannel(int row) {
    if (widget.channels.isEmpty) return;
    final target = row.clamp(0, widget.channels.length - 1);
    _revealAndRequest(
      _channelNode(target),
      verticalOffset: math.max(0, (target - 1) * _rowHeight),
    );
  }

  void _requestProgramme(int row, int index) {
    if (widget.channels.isEmpty || row < 0 || row >= widget.channels.length) {
      return;
    }
    final programmes = _guide[widget.channels[row].streamId] ?? const [];
    if (programmes.isEmpty) {
      _requestChannel(row);
      return;
    }
    final target = index.clamp(0, programmes.length - 1);
    final programme = programmes[target];
    final startSlot =
        (programme.startUtc.difference(_windowStart).inMinutes /
                _guideSlot.inMinutes)
            .floor()
            .clamp(0, _slotCount - 1);
    _revealAndRequest(
      _programmeNode(row, programme),
      verticalOffset: math.max(0, (row - 1) * _rowHeight),
      horizontalOffset: math.max(0, (startSlot - 1) * _slotWidth),
    );
  }

  void _revealAndRequest(
    FocusNode node, {
    double? verticalOffset,
    double? horizontalOffset,
  }) {
    if (verticalOffset != null && _vertical.hasClients) {
      _vertical.jumpTo(
        verticalOffset.clamp(
          _vertical.position.minScrollExtent,
          _vertical.position.maxScrollExtent,
        ),
      );
    }
    if (horizontalOffset != null && _horizontal.hasClients) {
      _horizontal.jumpTo(
        horizontalOffset.clamp(
          _horizontal.position.minScrollExtent,
          _horizontal.position.maxScrollExtent,
        ),
      );
    }

    void attempt(int frames) {
      if (!mounted) return;
      final targetContext = node.context;
      if (targetContext != null &&
          targetContext.mounted &&
          node.canRequestFocus) {
        node.requestFocus();
        return;
      }
      if (frames > 0) {
        WidgetsBinding.instance.addPostFrameCallback(
          (_) => attempt(frames - 1),
        );
        WidgetsBinding.instance.ensureVisualUpdate();
      }
    }

    attempt(8);
  }

  void _scheduleInitialNowPosition([int attempts = 8]) {
    if (_positionedAtNow || _loading) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _positionedAtNow) return;
      if (!_horizontal.hasClients) {
        if (attempts > 0) _scheduleInitialNowPosition(attempts - 1);
        return;
      }
      _positionedAtNow = true;
      _scrollToNow(focusProgramme: false);
    });
  }

  void _goNow() => _scrollToNow(focusProgramme: true);

  void _scrollToNow({required bool focusProgramme}) {
    final now = DateTime.now().toUtc();
    final slot = (now.difference(_windowStart).inMinutes / _guideSlot.inMinutes)
        .floor()
        .clamp(0, _slotCount - 1);
    if (_horizontal.hasClients) {
      _horizontal.animateTo(
        math.max(0, (slot - 1) * _slotWidth),
        duration: const Duration(milliseconds: 260),
        curve: Curves.easeOutCubic,
      );
    }
    if (!focusProgramme || widget.channels.isEmpty) return;
    final row = _selectedChannel == null
        ? 0
        : widget.channels.indexWhere(
            (channel) => channel.streamId == _selectedChannel!.streamId,
          );
    final programmes =
        _guide[widget.channels[math.max(0, row)].streamId] ?? const [];
    final index = closestProgrammeIndexByTime(programmes, now);
    if (index >= 0) _requestProgramme(math.max(0, row), index);
  }

  String _timeLabel(BuildContext context, DateTime utc) =>
      MaterialLocalizations.of(context).formatTimeOfDay(
        TimeOfDay.fromDateTime(utc.toLocal()),
        alwaysUse24HourFormat: MediaQuery.alwaysUse24HourFormatOf(context),
      );

  String _durationLabel(EpgProgramme programme) =>
      '${_timeLabel(context, programme.startUtc)} – '
      '${_timeLabel(context, programme.stopUtc)}';

  void _selectProgramme(int row, EpgProgramme programme) {
    setState(() {
      _selected = programme;
      _selectedChannel = widget.channels[row];
    });
    final now = DateTime.now().toUtc();
    if (!programme.startUtc.isAfter(now) && programme.stopUtc.isAfter(now)) {
      _play(row);
    }
  }

  @override
  Widget build(BuildContext context) {
    final phone = !isWide(context) && !_isTv;
    final hasProgrammes = _guide.values.any((values) => values.isNotEmpty);
    final showEmpty =
        !_loading && !hasProgrammes && !widget.repository.guideRefreshing;
    return Scaffold(
      backgroundColor: widget.embedded ? Colors.transparent : bg,
      body: SafeArea(
        top: !widget.embedded,
        bottom: !widget.embedded,
        child: Column(
          children: [
            _toolbar(),
            Expanded(
              child: _loading && _guide.isEmpty
                  ? const GridLoading(channel: true)
                  : showEmpty
                  ? _emptyGuide()
                  : phone
                  ? _agenda()
                  : _grid(),
            ),
            if (!phone && !showEmpty) _detailsPanel(),
          ],
        ),
      ),
    );
  }

  Widget _emptyGuide() {
    final status = widget.repository.guideStatus.trim();
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520),
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 64,
                height: 64,
                decoration: BoxDecoration(
                  color: accentInk.withValues(alpha: isDark ? .14 : .09),
                  borderRadius: BorderRadius.circular(lumenCorner(20)),
                  border: Border.all(color: lineStrong),
                ),
                child: Icon(
                  Icons.calendar_month_outlined,
                  color: accentInk,
                  size: 30,
                ),
              ),
              const SizedBox(height: 18),
              Text(
                'No programme schedule available',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: textHi,
                  fontSize: _isTv ? 23 : 20,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                status.isNotEmpty
                    ? status
                    : 'This IPTV service did not return programme listings for these channels. Live TV can still be played normally.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: muted,
                  fontSize: _isTv ? 15 : 13,
                  height: 1.45,
                ),
              ),
              const SizedBox(height: 18),
              OutlinedButton.icon(
                focusNode: _emptyRefreshFocus,
                onPressed: _refresh,
                icon: const Icon(Icons.refresh_rounded, size: 18),
                label: const Text('Try again'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _refresh() async {
    await widget.repository.ensureFullGuide(force: true);
    await _readWindow();
  }

  Widget _toolbar() => Padding(
    padding: EdgeInsets.fromLTRB(_isTv ? 38 : 14, 14, _isTv ? 38 : 14, 12),
    child: Row(
      children: [
        if (widget.showBackButton) ...[
          _GuideAction(
            focusNode: _backFocus,
            icon: Icons.arrow_back_rounded,
            label: 'Live',
            onTap: () => Navigator.of(context).pop(),
            onDown: () => _requestChannel(0),
          ),
          const SizedBox(width: 14),
        ],
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                widget.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: textHi,
                  fontSize: _isTv ? 27 : 22,
                  fontWeight: FontWeight.w800,
                ),
              ),
              if (widget.repository.guideRefreshing ||
                  widget.repository.guideStatus.isNotEmpty)
                Text(
                  widget.repository.guideRefreshing
                      ? 'Updating guide quietly…'
                      : widget.repository.guideStatus,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: muted, fontSize: 12),
                ),
            ],
          ),
        ),
        if (widget.repository.guideRefreshing)
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: SizedBox(
              width: 17,
              height: 17,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: accentInk,
              ),
            ),
          ),
        _GuideAction(
          focusNode: _refreshFocus,
          icon: Icons.refresh_rounded,
          label: 'Refresh',
          onTap: _refresh,
          onDown: () => _requestChannel(0),
        ),
        const SizedBox(width: 8),
        _GuideAction(
          focusNode: _nowFocus,
          autofocus: _isTv && widget.showBackButton,
          icon: Icons.my_location_rounded,
          label: 'Now',
          onTap: _goNow,
          onDown: () => _requestChannel(0),
        ),
      ],
    ),
  );

  Widget _grid() => Padding(
    padding: EdgeInsets.symmetric(horizontal: _isTv ? 38 : 14),
    child: ClipRRect(
      borderRadius: BorderRadius.circular(lumenCorner(16)),
      child: Stack(
        children: [
          TableView.builder(
            verticalDetails: ScrollableDetails.vertical(controller: _vertical),
            horizontalDetails: ScrollableDetails.horizontal(
              controller: _horizontal,
            ),
            diagonalDragBehavior: DiagonalDragBehavior.free,
            pinnedRowCount: 1,
            pinnedColumnCount: 1,
            rowCount: widget.channels.length + 1,
            columnCount: _slotCount + 1,
            rowBuilder: (index) => TableSpan(
              extent: FixedTableSpanExtent(index == 0 ? 50 : _rowHeight),
              backgroundDecoration: TableSpanDecoration(
                color: index == 0 ? surfaceHi : surface,
                border: TableSpanBorder(
                  trailing: BorderSide(color: line, width: 1),
                ),
              ),
            ),
            columnBuilder: (index) => TableSpan(
              extent: FixedTableSpanExtent(
                index == 0 ? _channelWidth : _slotWidth,
              ),
              backgroundDecoration: TableSpanDecoration(
                color: index == 0 ? surfaceHi : surface,
                border: TableSpanBorder(
                  trailing: BorderSide(color: line, width: 1),
                ),
              ),
            ),
            cellBuilder: _buildGridCell,
          ),
          Positioned.fill(
            child: IgnorePointer(
              child: AnimatedBuilder(
                animation: _horizontal,
                builder: (_, _) {
                  final minutes =
                      DateTime.now()
                          .toUtc()
                          .difference(_windowStart)
                          .inSeconds /
                      60;
                  final x =
                      _channelWidth +
                      (minutes / _guideSlot.inMinutes) * _slotWidth -
                      (_horizontal.hasClients ? _horizontal.offset : 0);
                  return CustomPaint(
                    painter: _NowLinePainter(
                      x: x,
                      minimumX: _channelWidth,
                      headerHeight: 50,
                      color: accentInk,
                    ),
                  );
                },
              ),
            ),
          ),
        ],
      ),
    ),
  );

  TableViewCell _buildGridCell(BuildContext context, TableVicinity vicinity) {
    if (vicinity.row == 0 && vicinity.column == 0) {
      return TableViewCell(
        child: Container(
          alignment: Alignment.centerLeft,
          padding: const EdgeInsets.symmetric(horizontal: 14),
          color: surfaceHi,
          child: Text(
            'CHANNEL',
            style: TextStyle(
              color: muted,
              fontSize: 11,
              fontWeight: FontWeight.w800,
              letterSpacing: 1.2,
            ),
          ),
        ),
      );
    }
    if (vicinity.row == 0) {
      final instant = _windowStart.add(
        Duration(minutes: (vicinity.column - 1) * _guideSlot.inMinutes),
      );
      return TableViewCell(
        child: Container(
          alignment: Alignment.centerLeft,
          padding: const EdgeInsets.symmetric(horizontal: 10),
          color: surfaceHi,
          child: Text(
            instant.minute == 0 ? _timeLabel(context, instant) : '',
            style: TextStyle(
              color: textHi,
              fontSize: 12,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      );
    }
    final row = vicinity.row - 1;
    if (vicinity.column == 0) return _channelCell(row);
    final placed = _slots[(vicinity.row, vicinity.column)];
    if (placed == null) {
      return TableViewCell(
        child: ColoredBox(
          color: row.isEven
              ? surface.withValues(alpha: .88)
              : surfaceHi.withValues(alpha: .45),
        ),
      );
    }
    final key = _programmeKey(row, placed.programme);
    return _programmeCells.putIfAbsent(
      key,
      () => TableViewCell(
        columnMergeStart: placed.startColumn,
        columnMergeSpan: placed.span,
        child: _programmeCell(placed),
      ),
    );
  }

  TableViewCell _channelCell(int row) {
    final channel = widget.channels[row];
    return TableViewCell(
      child: RemoteTap(
        focusNode: _channelNode(row),
        showFocusRing: false,
        semanticLabel: channel.name,
        onTap: () => _play(row),
        onKeyEvent: (_, event) => _channelKeyEvent(row, event),
        child: AnimatedBuilder(
          animation: _channelNode(row),
          builder: (_, _) {
            final focused = _channelNode(row).hasFocus;
            return Container(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              decoration: BoxDecoration(
                color: focused ? accent.withValues(alpha: .18) : surfaceHi,
                border: Border.all(
                  color: focused ? accentInk : Colors.transparent,
                  width: focused ? activeFocusStyle.ringWidth : 0,
                ),
                boxShadow: focused ? lumenFocusShadows(accentInk) : null,
              ),
              child: Row(
                children: [
                  SizedBox(
                    width: 38,
                    height: 38,
                    child: channel.effectiveIcon.isEmpty
                        ? Icon(Icons.live_tv_rounded, color: muted, size: 22)
                        : MediaImage(
                            source: channel.effectiveIcon,
                            fit: BoxFit.contain,
                            error: Icon(
                              Icons.live_tv_rounded,
                              color: muted,
                              size: 22,
                            ),
                          ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      channel.name,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: textHi,
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _programmeCell(_PlacedProgramme placed) {
    final programme = placed.programme;
    final node = _programmeNode(placed.row, programme);
    final now = DateTime.now().toUtc();
    final airing =
        !programme.startUtc.isAfter(now) && programme.stopUtc.isAfter(now);
    return RemoteTap(
      focusNode: node,
      showFocusRing: false,
      semanticLabel: programme.title,
      onTap: () => _selectProgramme(placed.row, programme),
      onFocusChange: (focused) {
        if (!focused || !mounted) return;
        setState(() {
          _selected = programme;
          _selectedChannel = widget.channels[placed.row];
        });
        final start = math.max(0, placed.row - 4);
        final end = math.min(widget.channels.length, placed.row + 5);
        unawaited(
          widget.repository.primeVisible(widget.channels.sublist(start, end)),
        );
      },
      onKeyEvent: (_, event) =>
          _programmeKeyEvent(placed.row, placed.index, event),
      child: AnimatedBuilder(
        animation: node,
        builder: (_, _) => Container(
          key: ValueKey('guide-programme-${placed.row}-${placed.index}'),
          margin: const EdgeInsets.all(3),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          decoration: BoxDecoration(
            color: airing
                ? accent.withValues(alpha: .16)
                : surfaceHi.withValues(alpha: .72),
            borderRadius: BorderRadius.circular(lumenCorner(8)),
            border: Border.all(
              color: node.hasFocus
                  ? accentInk
                  : airing
                  ? accent.withValues(alpha: .55)
                  : line,
              width: node.hasFocus ? activeFocusStyle.ringWidth : 1,
            ),
            boxShadow: node.hasFocus ? lumenFocusShadows(accentInk) : null,
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                programme.title.isEmpty
                    ? 'Untitled programme'
                    : programme.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: textHi,
                  fontSize: 12.5,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 3),
              Text(
                _durationLabel(programme),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: muted, fontSize: 10.5),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _detailsPanel() {
    final programme = _selected;
    final channel = _selectedChannel;
    return Container(
      height: _isTv ? 104 : 88,
      margin: EdgeInsets.fromLTRB(
        _isTv ? 38 : 14,
        10,
        _isTv ? 38 : 14,
        _isTv ? 18 : 10,
      ),
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
      decoration: BoxDecoration(
        color: surface,
        borderRadius: BorderRadius.circular(lumenCorner(14)),
        border: Border.all(color: line),
      ),
      child: programme == null
          ? Row(
              children: [
                Icon(Icons.info_outline_rounded, color: muted, size: 20),
                const SizedBox(width: 10),
                Text(
                  'Focus a programme to see details.',
                  style: TextStyle(color: muted, fontWeight: FontWeight.w600),
                ),
              ],
            )
          : Row(
              children: [
                Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${channel?.name ?? ''}  ·  ${_durationLabel(programme)}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: accentInk,
                          fontSize: 11.5,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        programme.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: textHi,
                          fontSize: 16,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      if (programme.description.isNotEmpty)
                        Text(
                          programme.description,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(color: muted, fontSize: 11.5),
                        ),
                    ],
                  ),
                ),
                Text(
                  'Select current programme to play',
                  style: TextStyle(color: muted, fontSize: 11),
                ),
              ],
            ),
    );
  }

  Widget _agenda() => ListView.builder(
    padding: const EdgeInsets.fromLTRB(14, 0, 14, 100),
    itemCount: widget.channels.length,
    itemBuilder: (_, row) {
      final channel = widget.channels[row];
      final programmes = _guide[channel.streamId] ?? const <EpgProgramme>[];
      final now = DateTime.now().toUtc();
      final visible = programmes
          .where((programme) => programme.stopUtc.isAfter(now))
          .take(5)
          .toList(growable: false);
      return Card(
        margin: const EdgeInsets.only(bottom: 10),
        color: surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(lumenCorner(14)),
          side: BorderSide(color: line),
        ),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              RemoteTap(
                focusRadius: 10,
                semanticLabel: 'Play ${channel.name}',
                onTap: () => _play(row),
                child: Row(
                  children: [
                    SizedBox(
                      width: 40,
                      height: 40,
                      child: channel.effectiveIcon.isEmpty
                          ? Icon(Icons.live_tv_rounded, color: muted)
                          : MediaImage(
                              source: channel.effectiveIcon,
                              fit: BoxFit.contain,
                            ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        channel.name,
                        style: TextStyle(
                          color: textHi,
                          fontSize: 15,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                    Icon(Icons.play_arrow_rounded, color: accentInk),
                  ],
                ),
              ),
              const SizedBox(height: 9),
              if (visible.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Text(
                    'Guide unavailable',
                    style: TextStyle(color: muted, fontSize: 12),
                  ),
                )
              else
                for (final programme in visible)
                  RemoteTap(
                    focusRadius: 8,
                    semanticLabel:
                        '${programme.title}, ${_durationLabel(programme)}',
                    onTap: () => _selectProgramme(row, programme),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 7),
                      child: Row(
                        children: [
                          SizedBox(
                            width: 74,
                            child: Text(
                              _timeLabel(context, programme.startUtc),
                              style: TextStyle(color: muted, fontSize: 11.5),
                            ),
                          ),
                          Expanded(
                            child: Text(
                              programme.title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: textHi,
                                fontSize: 12.5,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
            ],
          ),
        ),
      );
    },
  );
}

class _PlacedProgramme {
  const _PlacedProgramme({
    required this.row,
    required this.index,
    required this.startColumn,
    required this.span,
    required this.programme,
  });

  final int row;
  final int index;
  final int startColumn;
  final int span;
  final EpgProgramme programme;
}

class _NowLinePainter extends CustomPainter {
  const _NowLinePainter({
    required this.x,
    required this.minimumX,
    required this.headerHeight,
    required this.color,
  });

  final double x;
  final double minimumX;
  final double headerHeight;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    if (x < minimumX || x > size.width) return;
    final paint = Paint()
      ..color = color
      ..strokeWidth = 2;
    canvas.drawLine(Offset(x, headerHeight), Offset(x, size.height), paint);
    canvas.drawCircle(Offset(x, headerHeight), 4, paint);
  }

  @override
  bool shouldRepaint(_NowLinePainter oldDelegate) =>
      x != oldDelegate.x ||
      minimumX != oldDelegate.minimumX ||
      headerHeight != oldDelegate.headerHeight ||
      color != oldDelegate.color;
}

class _GuideAction extends StatelessWidget {
  const _GuideAction({
    required this.focusNode,
    required this.icon,
    required this.label,
    required this.onTap,
    required this.onDown,
    this.autofocus = false,
  });

  final FocusNode focusNode;
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final VoidCallback onDown;
  final bool autofocus;

  @override
  Widget build(BuildContext context) => RemoteTap(
    focusNode: focusNode,
    autofocus: autofocus,
    showFocusRing: false,
    semanticLabel: label,
    onTap: onTap,
    onKeyEvent: (_, event) {
      if ((event is KeyDownEvent || event is KeyRepeatEvent) &&
          event.logicalKey == LogicalKeyboardKey.arrowDown) {
        onDown();
        return KeyEventResult.handled;
      }
      return KeyEventResult.ignored;
    },
    child: AnimatedBuilder(
      animation: focusNode,
      builder: (_, _) => AnimatedContainer(
        duration: const Duration(milliseconds: 120),
        padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 10),
        decoration: BoxDecoration(
          color: focusNode.hasFocus ? accent.withValues(alpha: .2) : surface,
          borderRadius: BorderRadius.circular(lumenCorner(11)),
          border: Border.all(
            color: focusNode.hasFocus ? accentInk : line,
            width: focusNode.hasFocus ? activeFocusStyle.ringWidth : 1,
          ),
          boxShadow: focusNode.hasFocus ? lumenFocusShadows(accentInk) : null,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              color: focusNode.hasFocus ? accentInk : textHi,
              size: 18,
            ),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                color: textHi,
                fontSize: 12.5,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    ),
  );
}
