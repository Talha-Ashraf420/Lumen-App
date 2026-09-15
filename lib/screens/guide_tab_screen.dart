import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../catalog_cache.dart';
import '../catalog_organization.dart';
import '../device_profile.dart';
import '../epg_repository.dart';
import '../models.dart';
import '../refresh.dart';
import '../responsive.dart';
import '../theme.dart';
import '../widgets.dart';
import '../xtream.dart';
import 'epg_guide_screen.dart';

/// First-class EPG destination. It loads one live category at a time so opening
/// Guide never requests a provider's entire live catalog or short EPG for
/// thousands of channels.
class GuideTabScreen extends StatefulWidget {
  const GuideTabScreen({
    super.key,
    required this.client,
    this.shellRailFocusNode,
    this.shellTopFocusNode,
    this.entryFocusNode,
    this.onExit,
  });

  final XtreamClient client;
  final FocusNode? shellRailFocusNode;
  final FocusNode? shellTopFocusNode;
  final FocusNode? entryFocusNode;
  final VoidCallback? onExit;

  @override
  State<GuideTabScreen> createState() => _GuideTabScreenState();
}

class _GuideTabScreenState extends State<GuideTabScreen>
    with AutomaticKeepAliveClientMixin {
  late final EpgRepository _repository;
  final Map<String, FocusNode> _categoryFocus = <String, FocusNode>{};
  final FocusNode _sourceFocus = FocusNode(debugLabel: 'Guide service filter');
  final GlobalKey<PopupMenuButtonState<String>> _sourceMenuKey = GlobalKey();
  List<Category> _rawCategories = const [];
  List<Category> _categories = const [];
  List<LiveStream> _channels = const [];
  String? _selectedId;
  String _selectedName = 'TV Guide';
  bool _loadingCategories = true;
  bool _loadingChannels = false;
  String _error = '';
  int _generation = 0;
  String _sourceScope = 'all';
  CatalogOrganization _organization = CatalogOrganization();

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _repository = EpgRepository(client: widget.client);
    _sourceFocus.onKeyEvent = _sourceKey;
    contentRefresh.addListener(_reload);
    CatalogOrganizationStore.instance.revision.addListener(
      _onOrganizationRevision,
    );
    unawaited(_loadCategories());
  }

  @override
  void dispose() {
    contentRefresh.removeListener(_reload);
    CatalogOrganizationStore.instance.revision.removeListener(
      _onOrganizationRevision,
    );
    _repository.dispose();
    _sourceFocus.onKeyEvent = null;
    _sourceFocus.dispose();
    for (final node in _categoryFocus.values) {
      node.dispose();
    }
    super.dispose();
  }

  FocusNode _nodeFor(String id, int index) {
    if (index == 0 && widget.entryFocusNode != null) {
      return widget.entryFocusNode!;
    }
    return _categoryFocus.putIfAbsent(
      id,
      () => FocusNode(debugLabel: 'Guide category $id'),
    );
  }

  FocusNode? get _selectedCategoryFocus {
    final selectedIndex = _categories.indexWhere(
      (category) => category.id == _selectedId,
    );
    if (selectedIndex < 0) return widget.entryFocusNode;
    return _nodeFor(_categories[selectedIndex].id, selectedIndex);
  }

  void _reload() {
    if (!mounted) return;
    unawaited(_loadCategories(preferredId: _selectedId));
  }

  void _onOrganizationRevision() =>
      unawaited(_loadCategories(preferredId: _selectedId));

  List<(String, String)> get _sources {
    final sources = <String, String>{};
    for (final category in _rawCategories) {
      if (category.sourceScope.isEmpty) continue;
      sources[category.sourceScope] = category.sourceLabel.isEmpty
          ? 'IPTV service'
          : category.sourceLabel;
    }
    return sources.entries.map((entry) => (entry.key, entry.value)).toList()
      ..sort((a, b) => a.$2.toLowerCase().compareTo(b.$2.toLowerCase()));
  }

  bool get _hasMultipleSources => _sources.length > 1;

  Future<void> _loadCategories({String? preferredId}) async {
    final generation = ++_generation;
    if (mounted) {
      setState(() {
        _loadingCategories = true;
        _error = '';
      });
    }
    try {
      final categories = await CatalogCache.instance.live(
        widget.client,
        priority: true,
      );
      final organization = await CatalogOrganizationStore.instance.load(
        widget.client.creds,
      );
      if (!mounted || generation != _generation) return;
      final organized = organization.apply(
        'live',
        categories,
        sourceScope: _sourceScope,
      );
      if (organized.isEmpty) {
        setState(() {
          _rawCategories = List.unmodifiable(categories);
          _organization = organization;
          _categories = const [];
          _channels = const [];
          _loadingCategories = false;
          _error = 'This account has no live-TV categories.';
        });
        return;
      }
      final selected = organized.firstWhere(
        (category) => category.id == preferredId,
        orElse: () => organized.first,
      );
      setState(() {
        _rawCategories = List.unmodifiable(categories);
        _organization = organization;
        _categories = List.unmodifiable(organized);
        _loadingCategories = false;
      });
      await _selectCategory(selected, generation: generation);
    } catch (_) {
      if (!mounted || generation != _generation) return;
      setState(() {
        _loadingCategories = false;
        _error = 'Lumen could not load the live-TV categories.';
      });
    }
  }

  Future<void> _selectCategory(Category category, {int? generation}) async {
    final requestGeneration = generation ?? ++_generation;
    setState(() {
      _selectedId = category.id;
      _selectedName = category.name;
      _channels = const [];
      _loadingChannels = true;
      _error = '';
    });
    try {
      final batches = await Future.wait(
        category.effectiveMemberIds.map(
          (id) => CatalogCache.instance.liveStreams(
            widget.client,
            id,
            priority: true,
          ),
        ),
      );
      final channels = <LiveStream>[
        for (final batch in batches)
          for (final channel in batch)
            if (!_organization.isHidden('live', channel.categoryId)) channel,
      ];
      if (!mounted || requestGeneration != _generation) return;
      setState(() {
        _channels = List.unmodifiable(channels);
        _loadingChannels = false;
        if (channels.isEmpty) {
          _error = 'This category has no live channels.';
        }
      });
    } catch (_) {
      if (!mounted || requestGeneration != _generation) return;
      setState(() {
        _loadingChannels = false;
        _error = 'Lumen could not load channels for this category.';
      });
    }
  }

  KeyEventResult _categoryKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    if (event.logicalKey == LogicalKeyboardKey.arrowLeft) {
      widget.shellRailFocusNode?.requestFocus();
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.arrowUp) {
      if (_hasMultipleSources &&
          _categories.isNotEmpty &&
          identical(node, _nodeFor(_categories.first.id, 0))) {
        _sourceFocus.requestFocus();
        return KeyEventResult.handled;
      }
      widget.shellTopFocusNode?.requestFocus();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  KeyEventResult _sourceKey(FocusNode _, KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    if (event.logicalKey == LogicalKeyboardKey.arrowLeft) {
      widget.shellRailFocusNode?.requestFocus();
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.arrowUp) {
      widget.shellTopFocusNode?.requestFocus();
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.arrowDown &&
        _categories.isNotEmpty) {
      _nodeFor(_categories.first.id, 0).requestFocus();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  void _selectSource(String value) {
    if (value == _sourceScope) return;
    setState(() => _sourceScope = value);
    unawaited(_loadCategories());
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final wide = isWide(context);
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: SafeArea(
        top: false,
        bottom: false,
        child: wide
            ? _loadingCategories
                  ? _loadingCategoryState()
                  : Row(
                      children: [
                        _categoryRail(),
                        Expanded(child: _guide()),
                      ],
                    )
            : Column(
                children: [
                  _mobileCategoryPicker(),
                  Expanded(
                    child: _loadingCategories
                        ? const GridLoading(channel: true)
                        : _guide(),
                  ),
                ],
              ),
      ),
    );
  }

  Widget _loadingCategoryState() => RemoteTap(
    focusNode: widget.entryFocusNode,
    semanticLabel: 'Loading channel groups',
    onTap: () {},
    onKeyEvent: _categoryKey,
    child: const GridLoading(channel: true),
  );

  Widget _guide() {
    if (_loadingChannels) return const GridLoading(channel: true);
    if (_channels.isEmpty) return _message(_error);
    return EpgGuideScreen(
      key: ValueKey('guide-category-$_selectedId'),
      client: widget.client,
      repository: _repository,
      channels: _channels,
      title: _selectedName,
      showBackButton: false,
      embedded: true,
      externalLeftFocusNode: _selectedCategoryFocus,
    );
  }

  Widget _categoryRail() => Container(
    width: DeviceProfile.isTelevision ? 238 : 210,
    decoration: BoxDecoration(
      color: surfaceHi.withValues(alpha: .62),
      border: Border(right: BorderSide(color: line)),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(18, 22, 14, 12),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  'CHANNEL GROUPS',
                  style: TextStyle(
                    color: muted,
                    fontSize: 10,
                    letterSpacing: 1.4,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              if (_hasMultipleSources) _sourcePicker(compact: true),
            ],
          ),
        ),
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.fromLTRB(10, 0, 10, 16),
            itemCount: _categories.length,
            itemBuilder: (_, index) {
              final category = _categories[index];
              final selected = category.id == _selectedId;
              return Padding(
                padding: const EdgeInsets.only(bottom: 3),
                child: RemoteTap(
                  focusNode: _nodeFor(category.id, index),
                  onKeyEvent: _categoryKey,
                  onTap: () => _selectCategory(category),
                  focusRadius: 11,
                  child: AnimatedContainer(
                    duration: lumenMotion,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 11,
                    ),
                    decoration: BoxDecoration(
                      color: selected
                          ? accentInk.withValues(alpha: isDark ? .14 : .09)
                          : Colors.transparent,
                      borderRadius: BorderRadius.circular(lumenCorner(11)),
                    ),
                    child: Text(
                      category.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: selected ? accentInk : textHi,
                        fontSize: 12.5,
                        fontWeight: selected
                            ? FontWeight.w800
                            : FontWeight.w600,
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ],
    ),
  );

  Widget _mobileCategoryPicker() => Padding(
    padding: const EdgeInsets.fromLTRB(14, 12, 14, 0),
    child: Row(
      children: [
        if (widget.onExit != null) ...[
          IconButton.outlined(
            tooltip: 'Back from guide',
            onPressed: widget.onExit,
            icon: const Icon(Icons.arrow_back_rounded, size: 19),
          ),
          const SizedBox(width: 8),
        ],
        Expanded(
          child: PopupMenuButton<String>(
            tooltip: 'Choose channel group',
            initialValue: _selectedId,
            onSelected: (id) {
              final category = _categories.firstWhere((item) => item.id == id);
              unawaited(_selectCategory(category));
            },
            itemBuilder: (_) => [
              for (final category in _categories)
                PopupMenuItem(value: category.id, child: Text(category.name)),
            ],
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
              decoration: BoxDecoration(
                color: surface,
                borderRadius: BorderRadius.circular(lumenCorner(13)),
                border: Border.all(color: line),
              ),
              child: Row(
                children: [
                  Icon(Icons.live_tv_rounded, color: accentInk, size: 19),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      _selectedName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: textHi,
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  Icon(Icons.expand_more_rounded, color: muted),
                ],
              ),
            ),
          ),
        ),
        if (_hasMultipleSources) ...[
          const SizedBox(width: 8),
          _sourcePicker(compact: true),
        ],
      ],
    ),
  );

  Widget _sourcePicker({bool compact = false}) => FocusableActionDetector(
    focusNode: _sourceFocus,
    shortcuts: const <ShortcutActivator, Intent>{
      SingleActivator(LogicalKeyboardKey.enter): ActivateIntent(),
      SingleActivator(LogicalKeyboardKey.numpadEnter): ActivateIntent(),
      SingleActivator(LogicalKeyboardKey.select): ActivateIntent(),
      SingleActivator(LogicalKeyboardKey.gameButtonA): ActivateIntent(),
    },
    actions: <Type, Action<Intent>>{
      ActivateIntent: CallbackAction<ActivateIntent>(
        onInvoke: (_) {
          _sourceMenuKey.currentState?.showButtonMenu();
          return null;
        },
      ),
    },
    child: ExcludeFocus(
      child: PopupMenuButton<String>(
        key: _sourceMenuKey,
        tooltip: 'Filter guide by service',
        onSelected: _selectSource,
        itemBuilder: (_) => [
          _sourceItem('all', 'All services'),
          for (final source in _sources) _sourceItem(source.$1, source.$2),
        ],
        child: Container(
          padding: EdgeInsets.symmetric(
            horizontal: compact ? 9 : 12,
            vertical: 9,
          ),
          decoration: BoxDecoration(
            color: _sourceFocus.hasFocus
                ? accent.withValues(alpha: .2)
                : surface,
            borderRadius: BorderRadius.circular(lumenCorner(11)),
            border: Border.all(color: _sourceFocus.hasFocus ? accentInk : line),
          ),
          child: Icon(Icons.dns_outlined, color: accentInk, size: 18),
        ),
      ),
    ),
  );

  PopupMenuItem<String> _sourceItem(String value, String label) =>
      PopupMenuItem(
        value: value,
        child: Row(
          children: [
            Icon(
              value == _sourceScope ? Icons.check_rounded : Icons.dns_outlined,
              color: value == _sourceScope ? accentInk : muted,
              size: 18,
            ),
            const SizedBox(width: 10),
            Flexible(child: Text(label, overflow: TextOverflow.ellipsis)),
          ],
        ),
      );

  Widget _message(String value) => Center(
    child: Padding(
      padding: const EdgeInsets.all(24),
      child: Text(
        value.isEmpty ? 'No channels are available.' : value,
        textAlign: TextAlign.center,
        style: TextStyle(color: muted, fontSize: 14),
      ),
    ),
  );
}
