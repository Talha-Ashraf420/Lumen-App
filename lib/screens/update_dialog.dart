import 'package:flutter/material.dart';
import '../theme.dart';
import '../updater.dart';

/// Shows the "Update available" dialog and runs the right install path per
/// platform (Android = download+install in-app; others = open release page).
Future<void> showUpdateFlow(BuildContext context, UpdateInfo info) async {
  await showDialog<void>(
    context: context,
    builder: (ctx) => _UpdateDialog(info: info),
  );
}

class _UpdateDialog extends StatefulWidget {
  final UpdateInfo info;
  const _UpdateDialog({required this.info});
  @override
  State<_UpdateDialog> createState() => _UpdateDialogState();
}

class _UpdateDialogState extends State<_UpdateDialog> {
  bool _busy = false;
  double _progress = 0;
  String? _error;

  Future<void> _run() async {
    final info = widget.info;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      if (Updater.instance.canSelfInstall && info.apkUrl != null) {
        await Updater.instance.downloadAndInstall(info, onProgress: (p) => setState(() => _progress = p));
        if (mounted) Navigator.of(context).pop();
      } else {
        await Updater.instance.openReleasePage(info);
        if (mounted) Navigator.of(context).pop();
      }
    } catch (e) {
      setState(() {
        _busy = false;
        _error = 'Update failed: $e';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final info = widget.info;
    final canInstall = Updater.instance.canSelfInstall && info.apkUrl != null;
    return AlertDialog(
      backgroundColor: surface,
      title: Row(children: [
        Icon(Icons.system_update_rounded, color: accent),
        const SizedBox(width: 10),
        const Expanded(child: Text('Update available')),
      ]),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(info.name, style: const TextStyle(fontWeight: FontWeight.w700)),
          if (info.notes.isNotEmpty) ...[
            const SizedBox(height: 8),
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 160),
              child: SingleChildScrollView(child: Text(info.notes, style: TextStyle(color: muted, fontSize: 13, height: 1.4))),
            ),
          ],
          if (!canInstall) ...[
            const SizedBox(height: 10),
            Text('This opens the release page to download the new build.', style: TextStyle(color: subtle, fontSize: 12)),
          ],
          if (_busy && canInstall) ...[
            const SizedBox(height: 16),
            ClipRRect(
              borderRadius: BorderRadius.circular(3),
              child: LinearProgressIndicator(
                value: _progress > 0 ? _progress : null,
                minHeight: 5,
                backgroundColor: surfaceHi,
                valueColor: AlwaysStoppedAnimation(accent),
              ),
            ),
            const SizedBox(height: 6),
            Text(_progress > 0 ? 'Downloading ${(_progress * 100).round()}%' : 'Starting…', style: TextStyle(color: subtle, fontSize: 12)),
          ],
          if (_error != null) ...[
            const SizedBox(height: 12),
            Text(_error!, style: const TextStyle(color: Color(0xFFFFB4B4), fontSize: 13)),
          ],
        ],
      ),
      actions: [
        TextButton(
          onPressed: _busy ? null : () => Navigator.of(context).pop(),
          child: Text('Later', style: TextStyle(color: muted)),
        ),
        FilledButton(
          style: FilledButton.styleFrom(backgroundColor: accent, foregroundColor: bg),
          onPressed: _busy ? null : _run,
          child: Text(canInstall ? 'Update now' : 'Get update'),
        ),
      ],
    );
  }
}
