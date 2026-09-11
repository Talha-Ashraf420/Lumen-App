import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../catalog_cache.dart';
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
  });

  final XtreamClient client;
  final FocusNode? shellRailFocusNode;
  final FocusNode? shellTopFocusNode;
  final FocusNode? entryFocusNode;

  @override
  State<GuideTabScreen> createState() => _GuideTabScreenState();
}

class _GuideTabScreenState extends State<GuideTabScreen>
    with AutomaticKeepAliveClientMixin {
  late final EpgRepository _repository;
  final Map<String, FocusNode> _categoryFocus = <String, FocusNode>{};
  List<Category> _categories = const [];
  List<LiveStream> _channels = const [];
  String? _selectedId;
  String _selectedName = 'TV Guide';
  bool _loadingCategories = true;
  bool _loadingChannels = false;
  String _error = '';
  int _generation = 0;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _repository = EpgRepository(client: widget.client);
    contentRefresh.addListener(_reload);
    unawaited(_loadCategories());
  }

  @override
  void dispose() {
    contentRefresh.removeListener(_reload);
    _repository.dispose();
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
      if (!mounted || generation != _generation) return;
      if (categories.isEmpty) {
        setState(() {
          _categories = const [];
          _channels = const [];
          _loadingCategories = false;
          _error = 'This account has no live-TV categories.';
        });
        return;
      }
      final selected = categories.firstWhere(
        (category) => category.id == preferredId,
        orElse: () => categories.first,
      );
      setState(() {
        _categories = List.unmodifiable(categories);
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
      final channels = await CatalogCache.instance.liveStreams(
        widget.client,
        category.id,
        priority: true,
      );
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

  KeyEventResult _categoryKey(FocusNode _, KeyEvent event) {
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
    return KeyEventResult.ignored;
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
        child: _loadingCategories
            ? _loadingCategoryState()
            : wide
            ? Row(
                children: [
                  _categoryRail(),
                  Expanded(child: _guide()),
                ],
              )
            : Column(
                children: [
                  _mobileCategoryPicker(),
                  Expanded(child: _guide()),
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
                      borderRadius: BorderRadius.circular(11),
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
          borderRadius: BorderRadius.circular(13),
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
