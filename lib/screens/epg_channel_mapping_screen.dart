import 'dart:async';

import 'package:flutter/material.dart';

import '../catalog_store.dart';
import '../epg.dart';
import '../epg_repository.dart';
import '../models.dart';
import '../store.dart';
import '../theme.dart';
import '../widgets.dart';
import '../xtream.dart';

class EpgChannelMappingScreen extends StatefulWidget {
  const EpgChannelMappingScreen({super.key, required this.client});

  final XtreamClient client;

  @override
  State<EpgChannelMappingScreen> createState() =>
      _EpgChannelMappingScreenState();
}

class _EpgChannelMappingScreenState extends State<EpgChannelMappingScreen> {
  static const int _pageSize = 80;

  late final EpgRepository _repository;
  late final String _scope;
  final _search = TextEditingController();
  final _scroll = ScrollController();
  final _channels = <LiveStream>[];
  List<_GuideSource> _sources = const [];
  Map<int, EpgChannelMapping> _manual = const {};
  Timer? _searchDebounce;
  bool _loadingSources = true;
  bool _loadingChannels = false;
  bool _hasMore = true;
  String _filter = 'unresolved';

  @override
  void initState() {
    super.initState();
    _repository = EpgRepository(client: widget.client);
    _scope = Store.profileScope(widget.client.creds);
    _scroll.addListener(_onScroll);
    unawaited(_loadSources());
    unawaited(_loadChannels(reset: true));
  }

  @override
  void dispose() {
    _repository.dispose();
    _searchDebounce?.cancel();
    _search.dispose();
    _scroll
      ..removeListener(_onScroll)
      ..dispose();
    super.dispose();
  }

  Future<void> _loadSources() async {
    final store = CatalogStore.instance;
    final states = await store.epgSourceStates(_scope);
    final sources = <_GuideSource>[];
    for (final state in states) {
      final channels = await store.epgChannels(_scope, state.sourceKey);
      if (channels.isEmpty) continue;
      sources.add(
        _GuideSource(
          key: state.sourceKey,
          label: 'Guide source ${sources.length + 1}',
          channels: channels,
        ),
      );
    }
    final mappings = await _repository.manualMappings();
    if (!mounted) return;
    setState(() {
      _sources = sources;
      _manual = {for (final mapping in mappings) mapping.liveStreamId: mapping};
      _loadingSources = false;
    });
  }

  Future<void> _loadChannels({required bool reset}) async {
    if (_loadingChannels || (!reset && !_hasMore)) return;
    setState(() => _loadingChannels = true);
    final offset = reset ? 0 : _channels.length;
    final page = await CatalogStore.instance.livePage(
      _scope,
      offset: offset,
      limit: _pageSize,
      query: _search.text,
      sort: 'az',
    );
    if (!mounted) return;
    setState(() {
      if (reset) _channels.clear();
      _channels.addAll(page.items);
      _hasMore = page.hasMore;
      _loadingChannels = false;
    });
  }

  void _onScroll() {
    if (_scroll.position.extentAfter < 500) {
      unawaited(_loadChannels(reset: false));
    }
  }

  void _onSearchChanged(String _) {
    _searchDebounce?.cancel();
    _searchDebounce = Timer(
      const Duration(milliseconds: 250),
      () => unawaited(_loadChannels(reset: true)),
    );
  }

  _MappingStatus _statusFor(LiveStream channel) {
    final manual = _manual[channel.streamId];
    if (manual != null) {
      for (final source in _sources) {
        if (source.key != manual.sourceKey) continue;
        for (final guide in source.channels) {
          if (guide.channelKey == manual.epgChannelKey) {
            return _MappingStatus(kind: 'manual', label: _guideName(guide));
          }
        }
      }
      return const _MappingStatus(
        kind: 'missing',
        label: 'Saved guide channel is unavailable',
      );
    }
    for (final source in _sources) {
      final key = matchEpgChannels([
        channel,
      ], source.channels)[channel.streamId];
      if (key == null) continue;
      final guide = source.channels.firstWhere(
        (item) => item.channelKey == key,
      );
      return _MappingStatus(kind: 'automatic', label: _guideName(guide));
    }
    return const _MappingStatus(kind: 'unresolved', label: 'No guide match');
  }

  bool _shows(_MappingStatus status) => switch (_filter) {
    'manual' => status.kind == 'manual' || status.kind == 'missing',
    'unresolved' => status.kind == 'unresolved' || status.kind == 'missing',
    _ => true,
  };

  Future<void> _openPicker(LiveStream channel) async {
    final changed = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => _EpgChannelPickerScreen(
          repository: _repository,
          liveChannel: channel,
          sources: _sources,
          current: _manual[channel.streamId],
        ),
      ),
    );
    if (changed != true) return;
    await _loadSources();
  }

  @override
  Widget build(BuildContext context) {
    final visible = [
      for (final channel in _channels)
        if (_shows(_statusFor(channel))) channel,
    ];
    if (!_loadingChannels && _hasMore && visible.length < 20) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) unawaited(_loadChannels(reset: false));
      });
    }
    return Scaffold(
      backgroundColor: bg,
      body: Stack(
        children: [
          const Aurora(),
          SafeArea(
            child: Column(
              children: [
                _header(),
                Padding(
                  padding: const EdgeInsets.fromLTRB(18, 2, 18, 12),
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      final compact = constraints.maxWidth < 680;
                      final search = RemoteTextInput(
                        child: TextField(
                          controller: _search,
                          onChanged: _onSearchChanged,
                          decoration: const InputDecoration(
                            prefixIcon: Icon(Icons.search_rounded),
                            hintText: 'Search live channels',
                          ),
                        ),
                      );
                      final filter = DropdownButtonFormField<String>(
                        initialValue: _filter,
                        decoration: const InputDecoration(labelText: 'Show'),
                        items: const [
                          DropdownMenuItem(
                            value: 'unresolved',
                            child: Text('Unresolved'),
                          ),
                          DropdownMenuItem(
                            value: 'manual',
                            child: Text('Manual'),
                          ),
                          DropdownMenuItem(
                            value: 'all',
                            child: Text('All channels'),
                          ),
                        ],
                        onChanged: (value) {
                          if (value != null) setState(() => _filter = value);
                        },
                      );
                      if (compact) {
                        return Column(
                          children: [
                            search,
                            const SizedBox(height: 10),
                            filter,
                          ],
                        );
                      }
                      return Row(
                        children: [
                          Expanded(child: search),
                          const SizedBox(width: 12),
                          SizedBox(width: 190, child: filter),
                        ],
                      );
                    },
                  ),
                ),
                Expanded(child: _body(visible)),
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
                'Channel mapping',
                style: TextStyle(fontSize: 21, fontWeight: FontWeight.w800),
              ),
              Text(
                'Fix missing or incorrect programme matches.',
                style: TextStyle(color: muted, fontSize: 12.5),
              ),
            ],
          ),
        ),
      ],
    ),
  );

  Widget _body(List<LiveStream> visible) {
    if (_loadingSources) {
      return Center(child: CircularProgressIndicator(color: accentInk));
    }
    if (_sources.isEmpty) {
      return _empty(
        Icons.calendar_view_week_outlined,
        'No downloaded guide source',
        'Go back and refresh the guide before mapping channels.',
      );
    }
    if (_channels.isEmpty && _loadingChannels) {
      return Center(child: CircularProgressIndicator(color: accentInk));
    }
    if (_channels.isEmpty) {
      return _empty(
        Icons.live_tv_outlined,
        'No cached live channels',
        'Open Live or refresh the library first. The mapper deliberately '
            'does not download the full provider catalog.',
      );
    }
    if (visible.isEmpty) {
      return _empty(
        Icons.task_alt_rounded,
        _filter == 'unresolved' ? 'Everything is matched' : 'No channels found',
        _filter == 'unresolved'
            ? 'Automatic and manual guide matching currently cover these cached channels.'
            : 'Try another search or filter.',
      );
    }
    return ListView.builder(
      controller: _scroll,
      padding: const EdgeInsets.fromLTRB(18, 0, 18, 36),
      itemCount: visible.length + (_loadingChannels ? 1 : 0),
      itemBuilder: (context, index) {
        if (index == visible.length) {
          return const Padding(
            padding: EdgeInsets.all(20),
            child: Center(child: CircularProgressIndicator()),
          );
        }
        final channel = visible[index];
        return Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: _channelRow(channel, _statusFor(channel)),
        );
      },
    );
  }

  Widget _channelRow(LiveStream channel, _MappingStatus status) {
    final highlighted = status.kind == 'manual';
    return RemoteTap(
      semanticLabel: 'Map ${channel.name}',
      focusRadius: 16,
      onTap: () => _openPicker(channel),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
        decoration: BoxDecoration(
          color: surface,
          borderRadius: BorderRadius.circular(lumenCorner(16)),
          border: Border.all(color: highlighted ? accentInk : line),
        ),
        child: Row(
          children: [
            Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                color: accentInk.withValues(alpha: .10),
                borderRadius: BorderRadius.circular(lumenCorner(12)),
              ),
              child: Icon(Icons.live_tv_rounded, color: accentInk, size: 20),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    channel.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.w800),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    '${_statusTitle(status.kind)} · ${status.label}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color:
                          status.kind == 'unresolved' ||
                              status.kind == 'missing'
                          ? dangerInk
                          : muted,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
            Icon(Icons.chevron_right_rounded, color: subtle),
          ],
        ),
      ),
    );
  }

  Widget _empty(IconData icon, String title, String message) => Center(
    child: Padding(
      padding: const EdgeInsets.all(28),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 500),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: accentInk, size: 40),
            const SizedBox(height: 14),
            Text(
              title,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 7),
            Text(
              message,
              textAlign: TextAlign.center,
              style: TextStyle(color: muted, height: 1.45),
            ),
          ],
        ),
      ),
    ),
  );

  String _statusTitle(String kind) => switch (kind) {
    'manual' => 'Manual',
    'automatic' => 'Automatic',
    'missing' => 'Needs attention',
    _ => 'Unresolved',
  };
}

class _EpgChannelPickerScreen extends StatefulWidget {
  const _EpgChannelPickerScreen({
    required this.repository,
    required this.liveChannel,
    required this.sources,
    required this.current,
  });

  final EpgRepository repository;
  final LiveStream liveChannel;
  final List<_GuideSource> sources;
  final EpgChannelMapping? current;

  @override
  State<_EpgChannelPickerScreen> createState() =>
      _EpgChannelPickerScreenState();
}

class _EpgChannelPickerScreenState extends State<_EpgChannelPickerScreen> {
  final _search = TextEditingController();
  late String _sourceKey;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _sourceKey =
        widget.sources.any((source) => source.key == widget.current?.sourceKey)
        ? widget.current!.sourceKey
        : widget.sources.first.key;
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  _GuideSource get _source =>
      widget.sources.firstWhere((source) => source.key == _sourceKey);

  List<EpgChannel> get _visibleChannels {
    final query = _search.text.trim().toLowerCase();
    if (query.isEmpty) return _source.channels;
    return _source.channels
        .where((channel) {
          return channel.channelKey.toLowerCase().contains(query) ||
              channel.displayNames.any(
                (name) => name.toLowerCase().contains(query),
              );
        })
        .toList(growable: false);
  }

  Future<void> _choose(EpgChannel channel) async {
    if (_saving) return;
    setState(() => _saving = true);
    await widget.repository.setManualMapping(
      liveStreamId: widget.liveChannel.streamId,
      sourceKey: _source.key,
      epgChannelKey: channel.channelKey,
    );
    if (mounted) Navigator.of(context).pop(true);
  }

  Future<void> _automatic() async {
    if (_saving) return;
    setState(() => _saving = true);
    await widget.repository.clearManualMapping(widget.liveChannel.streamId);
    if (mounted) Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    final channels = _visibleChannels;
    return Scaffold(
      backgroundColor: bg,
      body: Stack(
        children: [
          const Aurora(),
          SafeArea(
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(14, 10, 18, 12),
                  child: Row(
                    children: [
                      LumenBackButton(
                        onTap: () => Navigator.of(context).maybePop(),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              widget.liveChannel.name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 20,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                            Text(
                              'Choose the programme-guide channel',
                              style: TextStyle(color: muted, fontSize: 12.5),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(18, 2, 18, 12),
                  child: Column(
                    children: [
                      DropdownButtonFormField<String>(
                        initialValue: _sourceKey,
                        decoration: const InputDecoration(
                          labelText: 'Guide source',
                        ),
                        items: [
                          for (final source in widget.sources)
                            DropdownMenuItem(
                              value: source.key,
                              child: Text(source.label),
                            ),
                        ],
                        onChanged: (value) {
                          if (value != null) {
                            setState(() {
                              _sourceKey = value;
                              _search.clear();
                            });
                          }
                        },
                      ),
                      const SizedBox(height: 10),
                      RemoteTextInput(
                        child: TextField(
                          controller: _search,
                          onChanged: (_) => setState(() {}),
                          decoration: const InputDecoration(
                            prefixIcon: Icon(Icons.search_rounded),
                            hintText: 'Search guide channels',
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(18, 0, 18, 10),
                  child: SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: _saving ? null : _automatic,
                      icon: const Icon(Icons.auto_awesome_rounded),
                      label: const Text('Use automatic matching'),
                    ),
                  ),
                ),
                Expanded(
                  child: channels.isEmpty
                      ? Center(
                          child: Text(
                            'No guide channels match this search.',
                            style: TextStyle(color: muted),
                          ),
                        )
                      : ListView.builder(
                          padding: const EdgeInsets.fromLTRB(18, 0, 18, 36),
                          itemCount: channels.length,
                          itemBuilder: (context, index) {
                            final channel = channels[index];
                            final selected =
                                widget.current?.sourceKey == _sourceKey &&
                                widget.current?.epgChannelKey ==
                                    channel.channelKey;
                            return Padding(
                              padding: const EdgeInsets.only(bottom: 8),
                              child: RemoteTap(
                                semanticLabel: 'Use ${_guideName(channel)}',
                                focusRadius: 14,
                                onTap: _saving ? null : () => _choose(channel),
                                child: Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 16,
                                    vertical: 13,
                                  ),
                                  decoration: BoxDecoration(
                                    color: surface,
                                    borderRadius: BorderRadius.circular(
                                      lumenCorner(14),
                                    ),
                                    border: Border.all(
                                      color: selected ? accentInk : line,
                                    ),
                                  ),
                                  child: Row(
                                    children: [
                                      Icon(
                                        selected
                                            ? Icons.radio_button_checked_rounded
                                            : Icons.radio_button_off_rounded,
                                        color: selected ? accentInk : muted,
                                      ),
                                      const SizedBox(width: 12),
                                      Expanded(
                                        child: Text(
                                          _guideName(channel),
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: const TextStyle(
                                            fontWeight: FontWeight.w800,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            );
                          },
                        ),
                ),
              ],
            ),
          ),
          if (_saving)
            Positioned.fill(
              child: IgnorePointer(
                child: ColoredBox(
                  color: bg.withValues(alpha: .28),
                  child: Center(
                    child: CircularProgressIndicator(color: accentInk),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _GuideSource {
  const _GuideSource({
    required this.key,
    required this.label,
    required this.channels,
  });

  final String key;
  final String label;
  final List<EpgChannel> channels;
}

class _MappingStatus {
  const _MappingStatus({required this.kind, required this.label});

  final String kind;
  final String label;
}

String _guideName(EpgChannel channel) => channel.displayNames.isEmpty
    ? channel.channelKey
    : channel.displayNames.first;
