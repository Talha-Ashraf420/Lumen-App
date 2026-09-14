import 'dart:async';

import 'package:flutter/material.dart';

import '../epg_repository.dart';
import '../epg_settings.dart';
import '../theme.dart';
import '../widgets.dart';
import '../xtream.dart';
import 'epg_channel_mapping_screen.dart';

class EpgSettingsScreen extends StatefulWidget {
  const EpgSettingsScreen({super.key, required this.client});

  final XtreamClient client;

  @override
  State<EpgSettingsScreen> createState() => _EpgSettingsScreenState();
}

class _EpgSettingsScreenState extends State<EpgSettingsScreen> {
  late final EpgRepository _repository;
  final _url = TextEditingController();
  int _offsetMinutes = 0;
  EpgCacheDiagnostics? _diagnostics;
  bool _loading = true;
  bool _saving = false;
  bool _refreshing = false;
  bool _clearing = false;
  String? _urlError;

  @override
  void initState() {
    super.initState();
    _repository = EpgRepository(client: widget.client);
    unawaited(_load());
  }

  @override
  void dispose() {
    _repository.dispose();
    _url.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final settings = await EpgSettings.load(widget.client.creds);
    final diagnostics = await _repository.diagnostics();
    if (!mounted) return;
    setState(() {
      _url.text = settings.manualUrl;
      _offsetMinutes = settings.offsetMinutes;
      _diagnostics = diagnostics;
      _loading = false;
    });
  }

  Future<bool> _save({bool announce = true}) async {
    final error = EpgSettings.validateManualUrl(_url.text);
    if (error != null) {
      setState(() => _urlError = error);
      return false;
    }
    setState(() {
      _saving = true;
      _urlError = null;
    });
    try {
      await EpgSettings.save(
        widget.client.creds,
        manualUrl: _url.text,
        offsetMinutes: _offsetMinutes,
      );
      final diagnostics = await _repository.diagnostics();
      if (!mounted) return true;
      setState(() => _diagnostics = diagnostics);
      if (announce) _message('Guide settings saved');
      return true;
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _refresh() async {
    if (!await _save(announce: false) || !mounted) return;
    setState(() => _refreshing = true);
    try {
      await _repository.ensureFullGuide(force: true);
      final diagnostics = await _repository.diagnostics();
      if (!mounted) return;
      setState(() => _diagnostics = diagnostics);
      _message(
        _repository.guideStatus.isEmpty
            ? 'Guide refresh finished'
            : _repository.guideStatus,
      );
    } finally {
      if (mounted) setState(() => _refreshing = false);
    }
  }

  Future<void> _clearCache() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Clear guide cache?'),
        content: const Text(
          'This removes downloaded programme data for this account. '
          'Your guide sources and time correction stay saved.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Clear cache'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() => _clearing = true);
    try {
      await _repository.clearCache();
      final diagnostics = await _repository.diagnostics();
      if (!mounted) return;
      setState(() => _diagnostics = diagnostics);
      _message('Guide cache cleared');
    } finally {
      if (mounted) setState(() => _clearing = false);
    }
  }

  Future<void> _openMappings() async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => EpgChannelMappingScreen(client: widget.client),
      ),
    );
    final diagnostics = await _repository.diagnostics();
    if (mounted) setState(() => _diagnostics = diagnostics);
  }

  void _message(String text) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(text)));
  }

  @override
  Widget build(BuildContext context) {
    final compact = MediaQuery.sizeOf(context).width < 760;
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
                  child: _loading
                      ? Center(
                          child: CircularProgressIndicator(color: accentInk),
                        )
                      : SingleChildScrollView(
                          padding: EdgeInsets.fromLTRB(
                            compact ? 16 : 24,
                            4,
                            compact ? 16 : 24,
                            40,
                          ),
                          child: Center(
                            child: ConstrainedBox(
                              constraints: const BoxConstraints(maxWidth: 980),
                              child: FocusTraversalGroup(
                                policy: OrderedTraversalPolicy(),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    _sourceCard(),
                                    const SizedBox(height: 14),
                                    _statusCard(),
                                  ],
                                ),
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
    padding: const EdgeInsets.fromLTRB(14, 10, 18, 12),
    child: Row(
      children: [
        LumenBackButton(onTap: () => Navigator.of(context).maybePop()),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'TV guide setup',
                style: TextStyle(fontSize: 21, fontWeight: FontWeight.w800),
              ),
              Text(
                'Configure and inspect EPG data for this account.',
                style: TextStyle(color: muted, fontSize: 12.5),
              ),
            ],
          ),
        ),
      ],
    ),
  );

  Widget _sourceCard() => Glass(
    radius: 22,
    padding: const EdgeInsets.all(20),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Guide source & timing',
          style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 5),
        Text(
          'Lumen uses the provider guide automatically. Add a manual XMLTV '
          'source only when your provider supplies a separate guide URL.',
          style: TextStyle(color: muted, height: 1.4, fontSize: 13),
        ),
        const SizedBox(height: 18),
        FocusTraversalOrder(
          order: const NumericFocusOrder(1),
          child: RemoteTextInput(
            child: TextField(
              controller: _url,
              keyboardType: TextInputType.url,
              autocorrect: false,
              enableSuggestions: false,
              decoration: InputDecoration(
                labelText: 'Manual XMLTV URL (optional)',
                hintText: 'https://example.com/guide.xml',
                errorText: _urlError,
              ),
              onChanged: (_) {
                if (_urlError != null) setState(() => _urlError = null);
              },
            ),
          ),
        ),
        const SizedBox(height: 14),
        FocusTraversalOrder(
          order: const NumericFocusOrder(2),
          child: DropdownButtonFormField<int>(
            initialValue: _offsetMinutes,
            decoration: const InputDecoration(
              labelText: 'Guide time correction',
            ),
            items: [
              for (var minutes = -720; minutes <= 720; minutes += 30)
                DropdownMenuItem(
                  value: minutes,
                  child: Text(_offsetLabel(minutes)),
                ),
            ],
            onChanged: (value) {
              if (value != null) setState(() => _offsetMinutes = value);
            },
          ),
        ),
        const SizedBox(height: 8),
        Text(
          'Time correction changes what Lumen displays; cached provider times '
          'remain untouched.',
          style: TextStyle(color: subtle, fontSize: 11.5),
        ),
        const SizedBox(height: 18),
        Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            FocusTraversalOrder(
              order: const NumericFocusOrder(3),
              child: FilledButton.icon(
                onPressed: _saving || _refreshing ? null : _save,
                icon: _saving
                    ? const SizedBox.square(
                        dimension: 17,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.save_outlined),
                label: Text(_saving ? 'Saving…' : 'Save settings'),
              ),
            ),
            FocusTraversalOrder(
              order: const NumericFocusOrder(4),
              child: OutlinedButton.icon(
                onPressed: _refreshing || _saving ? null : _refresh,
                icon: _refreshing
                    ? const SizedBox.square(
                        dimension: 17,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.refresh_rounded),
                label: Text(_refreshing ? 'Refreshing…' : 'Refresh guide now'),
              ),
            ),
          ],
        ),
      ],
    ),
  );

  Widget _statusCard() {
    final data = _diagnostics;
    return Glass(
      radius: 22,
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Guide diagnostics',
                      style: TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Private cache information only—source URLs and '
                      'credentials are never shown here.',
                      style: TextStyle(color: muted, fontSize: 12.5),
                    ),
                  ],
                ),
              ),
              Icon(
                (data?.programmeCount ?? 0) > 0
                    ? Icons.check_circle_outline_rounded
                    : Icons.info_outline_rounded,
                color: accentInk,
              ),
            ],
          ),
          const SizedBox(height: 16),
          _metric('Sources cached', '${data?.sourceCount ?? 0}'),
          _metric('Sources ready', '${data?.readySourceCount ?? 0}'),
          _metric('Channels indexed', '${data?.channelCount ?? 0}'),
          _metric('Programmes indexed', '${data?.programmeCount ?? 0}'),
          _metric('Manual mappings', '${data?.manualMappingCount ?? 0}'),
          _metric('Last refreshed', _dateLabel(data?.lastFetchedAt)),
          _metric(
            'Guide coverage',
            data?.validFrom == null || data?.validUntil == null
                ? 'No cached window'
                : '${_dateLabel(data!.validFrom)} → ${_dateLabel(data.validUntil)}',
          ),
          if ((data?.lastError ?? '').isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              data!.lastError,
              style: TextStyle(color: dangerInk, fontSize: 12.5),
            ),
          ],
          const SizedBox(height: 16),
          FocusTraversalOrder(
            order: const NumericFocusOrder(5),
            child: FilledButton.icon(
              onPressed: _openMappings,
              icon: const Icon(Icons.account_tree_outlined),
              label: const Text('Manage channel mappings'),
            ),
          ),
          const SizedBox(height: 10),
          FocusTraversalOrder(
            order: const NumericFocusOrder(6),
            child: OutlinedButton.icon(
              onPressed: _clearing ? null : _clearCache,
              icon: _clearing
                  ? const SizedBox.square(
                      dimension: 17,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.delete_sweep_outlined),
              label: Text(_clearing ? 'Clearing…' : 'Clear guide cache'),
            ),
          ),
        ],
      ),
    );
  }

  Widget _metric(String label, String value) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 7),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Text(label, style: TextStyle(color: muted)),
        ),
        const SizedBox(width: 16),
        Flexible(
          child: Text(
            value,
            textAlign: TextAlign.end,
            style: const TextStyle(fontWeight: FontWeight.w700),
          ),
        ),
      ],
    ),
  );

  String _offsetLabel(int minutes) {
    if (minutes == 0) return 'Automatic / no correction';
    final sign = minutes > 0 ? '+' : '−';
    final absolute = minutes.abs();
    final hours = absolute ~/ 60;
    final remainder = absolute % 60;
    return '$sign${hours.toString().padLeft(2, '0')}:'
        '${remainder.toString().padLeft(2, '0')}';
  }

  String _dateLabel(DateTime? value) {
    if (value == null) return 'Never';
    final local = value.toLocal();
    String two(int part) => part.toString().padLeft(2, '0');
    return '${local.year}-${two(local.month)}-${two(local.day)} '
        '${two(local.hour)}:${two(local.minute)}';
  }
}
