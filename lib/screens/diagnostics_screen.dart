import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../device_profile.dart';
import '../diagnostics.dart';
import '../legal.dart';
import '../models.dart';
import '../theme.dart';
import '../responsive.dart';
import '../tv_playback_probe.dart';
import '../widgets.dart';

class DiagnosticsScreen extends StatefulWidget {
  const DiagnosticsScreen({super.key, required this.credentials});

  final XtreamCredentials credentials;

  @override
  State<DiagnosticsScreen> createState() => _DiagnosticsScreenState();
}

class _DiagnosticsScreenState extends State<DiagnosticsScreen> {
  final _notes = TextEditingController();
  String _report = '';
  bool _loading = true;
  bool _sharing = false;
  Map<String, Object?>? _tvReport;
  String? _tvReportStatus;

  @override
  void initState() {
    super.initState();
    _refreshReport();
    if (tvPlaybackProbeEnabled && DeviceProfile.isTelevision) {
      _refreshTvReport();
    }
  }

  @override
  void dispose() {
    _notes.dispose();
    super.dispose();
  }

  Future<String> _refreshReport() async {
    final report = await AppDiagnostics.instance.buildReport(
      credentials: widget.credentials,
      userNotes: _notes.text,
    );
    if (mounted) {
      setState(() {
        _report = report;
        _loading = false;
      });
    }
    return report;
  }

  Future<void> _copyReport() async {
    final report = await _refreshReport();
    await Clipboard.setData(ClipboardData(text: report));
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(const SnackBar(content: Text('Redacted report copied')));
  }

  Future<void> _shareReport(BuildContext originContext) async {
    if (_sharing) return;
    final box = originContext.findRenderObject();
    final origin = box is RenderBox
        ? box.localToGlobal(Offset.zero) & box.size
        : null;
    setState(() => _sharing = true);
    try {
      final report = await _refreshReport();
      if (!mounted) return;
      await AppDiagnostics.instance.shareReport(
        report,
        sharePositionOrigin: origin,
      );
    } finally {
      if (mounted) setState(() => _sharing = false);
    }
  }

  Future<void> _emailSupport() async {
    final report = await _refreshReport();
    await Clipboard.setData(ClipboardData(text: report));
    final uri = Uri(
      scheme: 'mailto',
      path: supportEmail,
      queryParameters: const {
        'subject': 'Lumen support request',
        'body':
            'My redacted Lumen diagnostic report is copied and ready to paste below.\n\n',
      },
    );
    final opened = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(
            opened
                ? 'Report copied — paste it into the email'
                : 'No email app opened. The report is still copied.',
          ),
        ),
      );
  }

  Future<void> _refreshTvReport() async {
    try {
      final report = await TvPlaybackProbe.read();
      if (mounted) setState(() => _tvReport = report);
    } catch (_) {
      if (mounted) {
        setState(
          () => _tvReportStatus = 'Could not read the TV playback trace.',
        );
      }
    }
  }

  Future<void> _copyTvReport() async {
    final report = _tvReport;
    if (report == null) return;
    await Clipboard.setData(
      ClipboardData(text: const JsonEncoder.withIndent('  ').convert(report)),
    );
    if (mounted) {
      setState(
        () => _tvReportStatus =
            'Playback trace copied. Share it only if you choose.',
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final compact = MediaQuery.sizeOf(context).width < 720;
    return Scaffold(
      backgroundColor: bg,
      body: Stack(
        children: [
          const Aurora(),
          SafeArea(
            child: Column(
              children: [
                _header(),
                Expanded(
                  child: SingleChildScrollView(
                    padding: EdgeInsets.fromLTRB(
                      pageGutter(context),
                      4,
                      pageGutter(context),
                      40,
                    ),
                    child: Center(
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 980),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            _privacyNotice(),
                            if (!DeviceProfile.isTelevision) ...[
                              const SizedBox(height: 14),
                              _notesCard(),
                            ],
                            const SizedBox(height: 14),
                            _actions(compact),
                            if (tvPlaybackProbeEnabled &&
                                DeviceProfile.isTelevision) ...[
                              const SizedBox(height: 14),
                              _tvPlaybackCard(),
                            ],
                            const SizedBox(height: 14),
                            _reportPreview(),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _header() => Padding(
    padding: pageInsets(context, bottom: 20),
    child: Row(
      children: [
        RemoteTap(
          autofocus: true,
          semanticLabel: 'Back from diagnostics',
          onTap: () => Navigator.of(context).maybePop(),
          focusRadius: 14,
          child: Container(
            width: 46,
            height: 46,
            decoration: BoxDecoration(
              color: surface,
              border: Border.all(color: line),
              borderRadius: BorderRadius.circular(lumenCorner(14)),
            ),
            child: Icon(Icons.arrow_back_rounded, color: textHi),
          ),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Diagnostics & feedback',
                style: TextStyle(fontSize: 21, fontWeight: FontWeight.w800),
              ),
              Text(
                'Review everything before you share it.',
                style: TextStyle(color: muted, fontSize: 12.5),
              ),
            ],
          ),
        ),
      ],
    ),
  );

  Widget _privacyNotice() => Glass(
    radius: 22,
    tint: accentInk.withValues(alpha: isDark ? 0.08 : 0.06),
    padding: const EdgeInsets.all(18),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 42,
          height: 42,
          decoration: BoxDecoration(
            color: accentInk.withValues(alpha: 0.13),
            borderRadius: BorderRadius.circular(lumenCorner(13)),
          ),
          child: Icon(Icons.visibility_outlined, color: accentInk, size: 21),
        ),
        const SizedBox(width: 13),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Private until you choose to share',
                style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
              ),
              const SizedBox(height: 5),
              Text(
                'Lumen does not upload this report. Provider addresses, usernames, passwords, playlist URLs, media titles and watch history are removed.',
                style: TextStyle(color: muted, height: 1.45, fontSize: 13),
              ),
            ],
          ),
        ),
      ],
    ),
  );

  Widget _notesCard() => Glass(
    radius: 22,
    padding: const EdgeInsets.all(18),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'What happened?',
          style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15),
        ),
        const SizedBox(height: 4),
        Text(
          'Optional. Do not enter credentials or private playlist details.',
          style: TextStyle(color: muted, fontSize: 12.5),
        ),
        const SizedBox(height: 12),
        RemoteTextInput(
          child: TextField(
            controller: _notes,
            readOnly: DeviceProfile.isTelevision,
            enableInteractiveSelection: !DeviceProfile.isTelevision,
            maxLength: 600,
            minLines: 2,
            maxLines: 4,
            textInputAction: TextInputAction.newline,
            decoration: const InputDecoration(
              hintText:
                  'Example: Live playback stalled after about 30 seconds…',
            ),
          ),
        ),
      ],
    ),
  );

  Widget _actions(bool compact) {
    final buttons = <Widget>[
      _actionButton(
        icon: Icons.copy_rounded,
        label: 'Copy report',
        onTap: _loading ? null : _copyReport,
      ),
      Builder(
        builder: (buttonContext) => _actionButton(
          icon: Icons.ios_share_rounded,
          label: _sharing ? 'Sharing…' : 'Share report',
          primary: true,
          onTap: _loading || _sharing
              ? null
              : () => _shareReport(buttonContext),
        ),
      ),
      if (!DeviceProfile.isTelevision)
        _actionButton(
          icon: Icons.email_outlined,
          label: 'Email support',
          onTap: _loading ? null : _emailSupport,
        ),
    ];
    return compact
        ? Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (var index = 0; index < buttons.length; index++) ...[
                buttons[index],
                if (index != buttons.length - 1) const SizedBox(height: 9),
              ],
            ],
          )
        : Wrap(spacing: 10, runSpacing: 10, children: buttons);
  }

  Widget _actionButton({
    required IconData icon,
    required String label,
    required VoidCallback? onTap,
    bool primary = false,
  }) => RemoteTap(
    semanticLabel: label,
    onTap: onTap,
    focusRadius: 16,
    child: AnimatedOpacity(
      opacity: onTap == null ? 0.55 : 1,
      duration: const Duration(milliseconds: 150),
      child: Container(
        constraints: const BoxConstraints(minWidth: 170, minHeight: 52),
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
        decoration: BoxDecoration(
          color: primary ? accent : surface,
          border: Border.all(color: primary ? accent : line),
          borderRadius: BorderRadius.circular(lumenCorner(16)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: primary ? onAccent : textHi, size: 20),
            const SizedBox(width: 9),
            Text(
              label,
              style: TextStyle(
                color: primary ? onAccent : textHi,
                fontWeight: FontWeight.w800,
              ),
            ),
          ],
        ),
      ),
    ),
  );

  Widget _reportPreview() => Glass(
    radius: 22,
    padding: const EdgeInsets.all(18),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(Icons.article_outlined, color: accentInk, size: 20),
            const SizedBox(width: 9),
            const Expanded(
              child: Text(
                'Report preview',
                style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15),
              ),
            ),
            if (_loading)
              SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: accentInk,
                ),
              ),
          ],
        ),
        const SizedBox(height: 13),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: bg.withValues(alpha: 0.55),
            border: Border.all(color: line.withValues(alpha: 0.75)),
            borderRadius: BorderRadius.circular(lumenCorner(15)),
          ),
          child: SelectableText(
            _loading ? 'Preparing a private report…' : _report,
            style: TextStyle(
              color: textHi.withValues(alpha: 0.86),
              fontFamily: 'monospace',
              fontSize: 11.5,
              height: 1.45,
            ),
          ),
        ),
      ],
    ),
  );

  Widget _tvPlaybackCard() => Glass(
    radius: 22,
    padding: const EdgeInsets.all(18),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'TV playback test',
          style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
        ),
        const SizedBox(height: 6),
        Text(
          'After a channel fails, press Back and return here. Only the player states, '
          'track counts, error codes and timing below can be copied if you choose. '
          'No channel name, stream address or account details are included.',
          style: TextStyle(color: muted, height: 1.4),
        ),
        const SizedBox(height: 12),
        SelectableText(
          _tvReport == null
              ? 'No TV playback trace yet. Try a channel first.'
              : const JsonEncoder.withIndent('  ').convert(_tvReport),
          style: TextStyle(
            color: textHi,
            fontFamily: 'monospace',
            fontSize: 12,
          ),
        ),
        if (_tvReportStatus != null) ...[
          const SizedBox(height: 10),
          Text(_tvReportStatus!, style: TextStyle(color: textHi)),
        ],
        const SizedBox(height: 14),
        Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            _actionButton(
              icon: Icons.refresh_rounded,
              label: 'Refresh trace',
              onTap: _refreshTvReport,
            ),
            _actionButton(
              icon: Icons.copy_rounded,
              label: 'Copy playback trace',
              primary: true,
              onTap: _tvReport == null ? null : _copyTvReport,
            ),
          ],
        ),
      ],
    ),
  );
}
