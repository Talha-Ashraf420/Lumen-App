import 'package:flutter/material.dart';
import '../theme.dart';
import '../updater.dart';

/// Shows the desktop update notice and opens the project's release page.
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
  String? _error;

  Future<void> _run() async {
    final info = widget.info;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await Updater.instance.openReleasePage(info);
      if (mounted) Navigator.of(context).pop();
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
          const SizedBox(height: 10),
          Text('This opens the release page in your browser.', style: TextStyle(color: subtle, fontSize: 12)),
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
          child: const Text('Get update'),
        ),
      ],
    );
  }
}
