import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';
import '../downloads.dart';
import '../playback.dart';
import '../theme.dart';
import '../widgets.dart';
import '../xtream.dart';

/// Offline downloads library: shows downloading/ready items, plays the local
/// file, and lets you remove them.
class DownloadsScreen extends StatefulWidget {
  final XtreamClient client;
  final FocusNode? shellRailFocusNode;
  const DownloadsScreen({
    super.key,
    required this.client,
    this.shellRailFocusNode,
  });

  @override
  State<DownloadsScreen> createState() => _DownloadsScreenState();
}

class _DownloadsScreenState extends State<DownloadsScreen> {
  String _filter = 'all';
  final _gridScroll = ScrollController();
  final _filterFocus = List<FocusNode>.generate(
    3,
    (index) => FocusNode(debugLabel: 'Downloads filter $index'),
  );
  final List<FocusNode> _itemFocus = <FocusNode>[];
  int _gridColumns = 1;
  static const double _rowExtent = 116;

  @override
  void dispose() {
    _gridScroll.dispose();
    for (final node in _filterFocus) {
      node.dispose();
    }
    for (final node in _itemFocus) {
      node.dispose();
    }
    super.dispose();
  }

  void _ensureItemFocus(int count) {
    while (_itemFocus.length < count) {
      _itemFocus.add(
        FocusNode(debugLabel: 'Download item ${_itemFocus.length}'),
      );
    }
  }

  void _requestItemFocus(int requested, int itemCount) {
    if (itemCount == 0) return;
    final target = requested.clamp(0, itemCount - 1).toInt();

    void attempt(int frames) {
      if (!mounted || target >= _itemFocus.length) return;
      final node = _itemFocus[target];
      if (node.context != null && node.canRequestFocus) {
        node.requestFocus();
        return;
      }
      if (_gridScroll.hasClients && _gridScroll.position.hasContentDimensions) {
        final desired = ((target ~/ _gridColumns) * _rowExtent).clamp(
          _gridScroll.position.minScrollExtent,
          _gridScroll.position.maxScrollExtent,
        );
        _gridScroll.jumpTo(desired);
      }
      if (frames > 0) {
        WidgetsBinding.instance.addPostFrameCallback(
          (_) => attempt(frames - 1),
        );
      }
    }

    attempt(8);
  }

  KeyEventResult _filterKey(int index, int itemCount, KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    if (event.logicalKey == LogicalKeyboardKey.arrowLeft) {
      if (index == 0) {
        widget.shellRailFocusNode?.requestFocus();
      } else {
        _filterFocus[index - 1].requestFocus();
      }
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.arrowRight) {
      _filterFocus[(index + 1).clamp(0, _filterFocus.length - 1).toInt()]
          .requestFocus();
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.arrowDown) {
      _requestItemFocus(index, itemCount);
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.arrowUp) {
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  KeyEventResult _itemKey(int index, int itemCount, KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    final column = index % _gridColumns;
    if (event.logicalKey == LogicalKeyboardKey.arrowUp) {
      if (index < _gridColumns) {
        _filterFocus[column.clamp(0, _filterFocus.length - 1).toInt()]
            .requestFocus();
      } else {
        _requestItemFocus(index - _gridColumns, itemCount);
      }
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.arrowDown) {
      if (index + _gridColumns < itemCount) {
        _requestItemFocus(index + _gridColumns, itemCount);
      }
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.arrowLeft &&
        _itemFocus[index].hasFocus &&
        column == 0) {
      widget.shellRailFocusNode?.requestFocus();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  void _play(DownloadItem d) {
    final path = Downloads.instance.localPath(d.id);
    if (path == null) return;
    PlaybackController.instance.open([
      PlayerItem(path, d.title, progressKey: d.progressKey, poster: d.poster),
    ], 0);
  }

  String _bytes(int b) {
    if (b <= 0) return '';
    const u = ['B', 'KB', 'MB', 'GB'];
    var v = b.toDouble();
    var i = 0;
    while (v >= 1024 && i < u.length - 1) {
      v /= 1024;
      i++;
    }
    return '${v.toStringAsFixed(v >= 10 || i == 0 ? 0 : 1)} ${u[i]}';
  }

  List<DownloadItem> _visible(List<DownloadItem> items) => switch (_filter) {
    'ready' =>
      items.where((item) => item.status == DlStatus.completed).toList(),
    'active' =>
      items.where((item) => item.status != DlStatus.completed).toList(),
    _ => items,
  };

  @override
  Widget build(BuildContext context) {
    // Self-contained (Scaffold) so it renders correctly whether it's a sidebar
    // tab (wrapped by the shell) or pushed as a route from Profile.
    final canBack = Navigator.of(context).canPop();
    return Scaffold(
      // Transparent as a tab (Aurora shows through, like other tabs); solid when
      // pushed as its own route so there's no black backdrop.
      backgroundColor: canBack ? bg : Colors.transparent,
      body: SafeArea(
        child: AnimatedBuilder(
          animation: Downloads.instance,
          builder: (_, child) {
            final items = Downloads.instance.items;
            final visible = _visible(items);
            _ensureItemFocus(visible.length);
            final ready = items
                .where((item) => item.status == DlStatus.completed)
                .length;
            final active = items.length - ready;
            final totalBytes = items
                .where((item) => item.status == DlStatus.completed)
                .fold<int>(0, (sum, item) => sum + item.received);
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                EditorialPageHeader(
                  eyebrow: 'Offline library',
                  title: canBack ? 'Downloads' : 'Ready when you are',
                  subtitle: ready == 0
                      ? 'Save films and episodes for moments without a connection.'
                      : '$ready ready offline${totalBytes > 0 ? ' · ${_bytes(totalBytes)}' : ''}',
                  icon: Icons.download_done_rounded,
                  onBack: canBack ? () => Navigator.of(context).pop() : null,
                  trailing: Downloads.instance.folderPath == null
                      ? null
                      : RemoteTap(
                          onTap: () {
                            final path = Downloads.instance.folderPath;
                            if (path != null) launchUrl(Uri.file(path));
                          },
                          semanticLabel: 'Open downloads folder',
                          focusRadius: 14,
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 13,
                              vertical: 10,
                            ),
                            decoration: BoxDecoration(
                              color: surfaceHi.withValues(alpha: 0.7),
                              borderRadius: BorderRadius.circular(14),
                              border: Border.all(color: line),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  Icons.folder_open_rounded,
                                  color: accentInk,
                                  size: 17,
                                ),
                                if (MediaQuery.sizeOf(context).width >=
                                    620) ...[
                                  const SizedBox(width: 7),
                                  const Text(
                                    'Open folder',
                                    style: TextStyle(
                                      fontWeight: FontWeight.w700,
                                      fontSize: 12.5,
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ),
                        ),
                ),
                if (items.isNotEmpty)
                  SizedBox(
                    height: 46,
                    child: ListView(
                      scrollDirection: Axis.horizontal,
                      padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
                      children: [
                        LumenFilterPill(
                          focusNode: _filterFocus[0],
                          onKeyEvent: (_, event) =>
                              _filterKey(0, visible.length, event),
                          label: 'All ${items.length}',
                          icon: Icons.grid_view_rounded,
                          selected: _filter == 'all',
                          onTap: () => setState(() => _filter = 'all'),
                        ),
                        const SizedBox(width: 8),
                        LumenFilterPill(
                          focusNode: _filterFocus[1],
                          onKeyEvent: (_, event) =>
                              _filterKey(1, visible.length, event),
                          label: 'Ready $ready',
                          icon: Icons.offline_pin_rounded,
                          selected: _filter == 'ready',
                          onTap: () => setState(() => _filter = 'ready'),
                        ),
                        const SizedBox(width: 8),
                        LumenFilterPill(
                          focusNode: _filterFocus[2],
                          onKeyEvent: (_, event) =>
                              _filterKey(2, visible.length, event),
                          label: 'In progress $active',
                          icon: Icons.downloading_rounded,
                          selected: _filter == 'active',
                          onTap: () => setState(() => _filter = 'active'),
                        ),
                      ],
                    ),
                  ),
                Expanded(
                  child: items.isEmpty
                      ? const LumenEmptyState(
                          icon: Icons.download_for_offline_outlined,
                          eyebrow: 'Take it with you',
                          title: 'Your offline shelf is empty',
                          message:
                              'Use the download button on a film or episode and Lumen will keep it ready here.',
                        )
                      : visible.isEmpty
                      ? LumenEmptyState(
                          icon: Icons.filter_alt_off_rounded,
                          eyebrow: 'Nothing in this view',
                          title: 'Try another download filter',
                          message:
                              'Your downloads are safe—this filter simply has no matching items.',
                          actionLabel: 'Show all downloads',
                          onAction: () => setState(() => _filter = 'all'),
                        )
                      : LayoutBuilder(
                          builder: (context, constraints) {
                            _gridColumns = (constraints.maxWidth / 620)
                                .ceil()
                                .clamp(1, visible.length)
                                .toInt();
                            return GridView.builder(
                              controller: _gridScroll,
                              padding: const EdgeInsets.fromLTRB(
                                18,
                                8,
                                18,
                                120,
                              ),
                              gridDelegate:
                                  const SliverGridDelegateWithMaxCrossAxisExtent(
                                    maxCrossAxisExtent: 620,
                                    mainAxisExtent: 104,
                                    crossAxisSpacing: 12,
                                    mainAxisSpacing: 12,
                                  ),
                              itemCount: visible.length,
                              itemBuilder: (_, i) =>
                                  _row(context, visible[i], i, visible.length),
                            );
                          },
                        ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _row(BuildContext context, DownloadItem d, int index, int itemCount) {
    final ready = d.status == DlStatus.completed;
    final failed = d.status == DlStatus.failed;
    return RemoteTap(
      focusNode: _itemFocus[index],
      onKeyEvent: (_, event) => _itemKey(index, itemCount, event),
      semanticLabel: d.title,
      onTap: () {
        if (ready) {
          _play(d);
        } else if (d.status == DlStatus.downloading) {
          Downloads.instance.pause(d.id);
        } else if (d.status == DlStatus.paused || failed) {
          Downloads.instance.resume(d.id);
        }
      },
      child: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: surfaceHi.withValues(alpha: 0.48),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: line),
        ),
        child: Row(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(11),
              child: SizedBox(
                width: 96,
                height: 60,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    ColoredBox(color: surfaceHi),
                    if (d.poster.isNotEmpty)
                      CachedNetworkImage(
                        imageUrl: d.poster,
                        fit: BoxFit.cover,
                        errorWidget: (_, _, _) => const SizedBox.shrink(),
                      ),
                    if (ready)
                      const Center(
                        child: Icon(
                          Icons.play_circle_fill_rounded,
                          color: Colors.white,
                          size: 28,
                        ),
                      ),
                  ],
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    d.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 14,
                      height: 1.2,
                    ),
                  ),
                  const SizedBox(height: 6),
                  if (ready)
                    Text(
                      'Ready · ${_bytes(d.received)}',
                      style: TextStyle(
                        color: accentInk,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    )
                  else if (failed)
                    Text(
                      d.errorMessage ?? 'Download failed — resume to retry',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Color(0xFFFF6B6B),
                        fontSize: 12,
                      ),
                    )
                  else if (d.status == DlStatus.queued)
                    Row(
                      children: [
                        Icon(Icons.schedule_rounded, color: muted, size: 14),
                        const SizedBox(width: 6),
                        Text(
                          'Queued — waiting for current download',
                          style: TextStyle(color: muted, fontSize: 12),
                        ),
                      ],
                    )
                  else ...[
                    Row(
                      children: [
                        Text(
                          d.status == DlStatus.paused
                              ? 'Paused'
                              : (d.total > 0
                                    ? '${(d.progress * 100).round()}%'
                                    : 'Downloading…'),
                          style: TextStyle(
                            color: d.status == DlStatus.paused ? muted : accent,
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          d.total > 0
                              ? '${_bytes(d.received)} / ${_bytes(d.total)}'
                              : _bytes(d.received),
                          style: TextStyle(color: subtle, fontSize: 11),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(2),
                      child: LinearProgressIndicator(
                        value: d.total > 0 ? d.progress : null,
                        minHeight: 3,
                        backgroundColor: surfaceHi,
                        valueColor: AlwaysStoppedAnimation(accent),
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(width: 2),
            if (d.status == DlStatus.downloading)
              _actionButton(
                Icons.pause_rounded,
                'Pause',
                () => Downloads.instance.pause(d.id),
              ),
            if (d.status == DlStatus.paused || d.status == DlStatus.failed)
              _actionButton(
                Icons.play_arrow_rounded,
                'Resume',
                () => Downloads.instance.resume(d.id),
              ),
            if (d.status == DlStatus.completed)
              _actionButton(
                Icons.delete_outline_rounded,
                'Remove',
                () => Downloads.instance.delete(d),
              )
            else
              _actionButton(
                Icons.close_rounded,
                'Cancel',
                () => Downloads.instance.cancel(d.id),
              ),
          ],
        ),
      ),
    );
  }

  Widget _actionButton(IconData icon, String label, VoidCallback onTap) =>
      Tooltip(
        message: label,
        child: RemoteTap(
          onTap: onTap,
          semanticLabel: label,
          focusRadius: 12,
          child: SizedBox(
            width: 42,
            height: 42,
            child: Icon(icon, color: accentInk, size: 22),
          ),
        ),
      );
}
