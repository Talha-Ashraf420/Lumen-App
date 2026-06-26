import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../downloads.dart';
import '../playback.dart';
import '../theme.dart';
import '../xtream.dart';

/// Offline downloads library: shows downloading/ready items, plays the local
/// file, and lets you remove them.
class DownloadsScreen extends StatelessWidget {
  final XtreamClient client;
  const DownloadsScreen({super.key, required this.client});

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
          builder: (_, __) {
            final items = Downloads.instance.items;
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: EdgeInsets.fromLTRB(canBack ? 6 : 18, 8, 16, 10),
                  child: Row(
                    children: [
                      if (canBack)
                        IconButton(
                          onPressed: () => Navigator.of(context).pop(),
                          icon: Icon(Icons.arrow_back_rounded, color: textHi),
                        ),
                      const Text('Downloads', style: TextStyle(fontSize: 28, fontWeight: FontWeight.w800, letterSpacing: -0.5)),
                      const SizedBox(width: 12),
                      Icon(Icons.download_rounded, color: accent, size: 22),
                      const Spacer(),
                      TextButton.icon(
                        onPressed: () {
                          final p = Downloads.instance.folderPath;
                          if (p != null) launchUrl(Uri.file(p));
                        },
                        icon: Icon(Icons.folder_open_rounded, color: accent, size: 18),
                        label: Text('Open folder', style: TextStyle(color: accent, fontWeight: FontWeight.w700, fontSize: 13)),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: items.isEmpty
                      ? _empty()
                      : ListView.separated(
                          padding: const EdgeInsets.fromLTRB(14, 4, 14, 120),
                          itemCount: items.length,
                          separatorBuilder: (_, __) => const SizedBox(height: 10),
                          itemBuilder: (_, i) => _row(context, items[i]),
                        ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _empty() => Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(22),
              decoration: BoxDecoration(color: surfaceHi.withValues(alpha: 0.5), shape: BoxShape.circle),
              child: Icon(Icons.download_for_offline_rounded, color: accent, size: 34),
            ),
            const SizedBox(height: 16),
            const Text('No downloads yet', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
            const SizedBox(height: 6),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 50),
              child: Text('Tap the download icon on a movie or episode to save it for offline viewing.',
                  textAlign: TextAlign.center, style: TextStyle(color: subtle, height: 1.4)),
            ),
          ],
        ),
      );

  Widget _row(BuildContext context, DownloadItem d) {
    final ready = d.status == DlStatus.completed;
    final failed = d.status == DlStatus.failed;
    return GestureDetector(
      onTap: ready ? () => _play(d) : null,
      child: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(color: surface, borderRadius: BorderRadius.circular(16), border: Border.all(color: line)),
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
                      CachedNetworkImage(imageUrl: d.poster, fit: BoxFit.cover, errorWidget: (_, _, _) => const SizedBox.shrink()),
                    if (ready) const Center(child: Icon(Icons.play_circle_fill_rounded, color: Colors.white, size: 28)),
                  ],
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(d.title, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14, height: 1.2)),
                  const SizedBox(height: 6),
                  if (ready)
                    Text('Ready · ${_bytes(d.received)}', style: TextStyle(color: accent, fontSize: 12, fontWeight: FontWeight.w600))
                  else if (failed)
                    Text('Failed — tap remove and retry', style: TextStyle(color: const Color(0xFFFF6B6B), fontSize: 12))
                  else if (d.status == DlStatus.queued)
                    Row(children: [
                      Icon(Icons.schedule_rounded, color: muted, size: 14),
                      const SizedBox(width: 6),
                      Text('Queued — waiting for current download', style: TextStyle(color: muted, fontSize: 12)),
                    ])
                  else ...[
                    Row(children: [
                      Text(
                          d.status == DlStatus.paused
                              ? 'Paused'
                              : (d.total > 0 ? '${(d.progress * 100).round()}%' : 'Downloading…'),
                          style: TextStyle(
                              color: d.status == DlStatus.paused ? muted : accent, fontSize: 12, fontWeight: FontWeight.w700)),
                      const SizedBox(width: 8),
                      Text(d.total > 0 ? '${_bytes(d.received)} / ${_bytes(d.total)}' : _bytes(d.received),
                          style: TextStyle(color: subtle, fontSize: 11)),
                    ]),
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
              IconButton(
                onPressed: () => Downloads.instance.pause(d.id),
                icon: Icon(Icons.pause_rounded, color: accent),
                tooltip: 'Pause',
              ),
            if (d.status == DlStatus.paused || d.status == DlStatus.failed)
              IconButton(
                onPressed: () => Downloads.instance.resume(d.id),
                icon: Icon(Icons.play_arrow_rounded, color: accent),
                tooltip: 'Resume',
              ),
            if (d.status == DlStatus.completed)
              IconButton(
                onPressed: () => Downloads.instance.delete(d),
                icon: Icon(Icons.delete_outline_rounded, color: muted),
                tooltip: 'Remove',
              )
            else
              IconButton(
                onPressed: () => Downloads.instance.cancel(d.id),
                icon: Icon(Icons.close_rounded, color: muted),
                tooltip: 'Cancel',
              ),
          ],
        ),
      ),
    );
  }
}
