import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../catalog_cache.dart';
import '../device_profile.dart';
import '../library.dart';
import '../refresh.dart';
import '../responsive.dart';
import '../models.dart';
import '../store.dart';
import '../theme.dart';
import '../widgets.dart';
import '../xtream.dart';
import '../playback.dart';
import 'movie_detail_screen.dart';
import 'series_detail_screen.dart';

String _year(String s) => RegExp(r'(19|20)\d{2}').firstMatch(s)?.group(0) ?? '';

class _Res {
  final String name, image, subtitle;
  final double rating;
  final bool live;
  final VoidCallback onTap;
  _Res(
    this.name,
    this.image,
    this.rating,
    this.subtitle,
    this.live,
    this.onTap,
  );
}

class SearchScreen extends StatefulWidget {
  final XtreamClient client;

  /// Stable shell-rail destination used when a TV user presses Left from the
  /// category column. Pushed catalog routes omit it and retain route-local
  /// traversal instead.
  final FocusNode? shellRailFocusNode;

  /// Stable command-bar destination above this page. Shell-hosted searches
  /// use it to leave the top search/sort control with remote Up.
  final FocusNode? shellTopFocusNode;

  /// When set ('movie' | 'series' | 'live'), the screen opens straight into
  /// that catalog (used by the desktop sidebar's Movies/Series/Live entries).
  final String? initialSection;

  /// Optional category to preselect (used by Home's "See all").
  final String? initialCategory;
  final String? initialCategoryName;
  const SearchScreen({
    super.key,
    required this.client,
    this.shellRailFocusNode,
    this.shellTopFocusNode,
    this.initialSection,
    this.initialCategory,
    this.initialCategoryName,
  });
  @override
  State<SearchScreen> createState() => SearchScreenState();
}

class SearchScreenState extends State<SearchScreen>
    with AutomaticKeepAliveClientMixin {
  final _ctrl = TextEditingController();
  final _searchFocus = FocusNode(debugLabel: 'Search library');
  final List<FocusNode> _sectionFocus = List.generate(
    4,
    (index) => FocusNode(
      debugLabel:
          'Search section ${const ['all', 'movie', 'series', 'live'][index]}',
    ),
  );
  final _categoryButtonFocus = FocusNode(debugLabel: 'Search category');
  final _categoryMenuKey = GlobalKey<PopupMenuButtonState<String>>();
  final _sortFocus = FocusNode(debugLabel: 'Catalog sort');
  final _sortMenuKey = GlobalKey<PopupMenuButtonState<String>>();
  final _gridScroll = ScrollController();
  final _categoryScope = FocusScopeNode(debugLabel: 'Catalog categories');
  final _gridScope = FocusScopeNode(debugLabel: 'Catalog content grid');
  final List<FocusNode> _gridFocus = <FocusNode>[];
  final Map<String, FocusNode> _categoryFocus = <String, FocusNode>{};
  final Map<String, List<FocusNode>> _searchResultFocus =
      <String, List<FocusNode>>{};
  final Map<String, int> _searchResultCounts = <String, int>{};
  final Map<String, ScrollController> _searchShelfScroll =
      <String, ScrollController>{};
  List<String> _visibleSearchGroups = const [];
  (int, int)? _pendingSearchFocus;
  int _searchFocusRequestSerial = 0;
  Timer? _categorySelectionTimer;
  Timer? _queryTimer;
  int _lastGridIndex = 0;
  int? _pendingGridFocus;
  int _gridFocusRequestSerial = 0;
  bool _gridFocusResumeScheduled = false;
  int _gridColumns = 1;
  double _gridRowExtent = 180;
  String _q = '';
  late String _section =
      widget.initialSection ?? 'all'; // all | movie | series | live
  late String _cat = widget.initialCategory ?? 'all';
  String _sort = 'default';

  // Streams cached per category id ('all' = whole catalog). Many providers
  // return nothing for the no-category "list all" call, so we fetch per
  // category (like Home does) and aggregate for the 'all' view.
  final Map<String, List<VodStream>> _movieByCat = {};
  final Map<String, List<Series>> _seriesByCat = {};
  final Map<String, List<LiveStream>> _liveByCat = {};
  final Set<String> _inFlight = {};
  final Map<String, bool> _hasMore = {};
  final Map<String, String> _cacheSignatures = {};
  int _resultGeneration = 0;
  static const _pageSize = 48;

  List<Category> _movieCats = [], _seriesCats = [], _liveCats = [];
  bool _movieCatsReady = false;
  bool _seriesCatsReady = false;
  bool _liveCatsReady = false;

  @override
  bool get wantKeepAlive => true;

  int get debugLoadedResultCount => switch (_section) {
    'movie' => _movieByCat[_cat]?.length ?? 0,
    'series' => _seriesByCat[_cat]?.length ?? 0,
    'live' => _liveByCat[_cat]?.length ?? 0,
    _ =>
      (_movieByCat['all']?.length ?? 0) +
          (_seriesByCat['all']?.length ?? 0) +
          (_liveByCat['all']?.length ?? 0),
  };

  @override
  void initState() {
    super.initState();
    _searchFocus.onKeyEvent = _moveSearchFieldFocus;
    _categoryButtonFocus
      ..onKeyEvent = _moveCategoryButtonFocus
      ..addListener(_onSortFocusChanged);
    _sortFocus
      ..onKeyEvent = _moveSortFocus
      ..addListener(_onSortFocusChanged);
    _loadCats();
    contentRefresh.addListener(_onRefresh);
    CatalogCache.instance.revision.addListener(_onCatalogRevision);
  }

  void _loadCats() {
    final c = widget.client;
    final wanted = widget.initialSection;
    if (wanted == null || wanted == 'movie') {
      CatalogCache.instance
          .vod(c, priority: true)
          .then((categories) => _storeCategories('movie', categories));
    }
    if (wanted == null || wanted == 'series') {
      CatalogCache.instance
          .series(c, priority: true)
          .then((categories) => _storeCategories('series', categories));
    }
    if (wanted == null || wanted == 'live') {
      CatalogCache.instance
          .live(c, priority: true)
          .then((categories) => _storeCategories('live', categories));
    }
  }

  void _storeCategories(String section, List<Category> categories) {
    if (!mounted) return;
    setState(() {
      switch (section) {
        case 'movie':
          _movieCats = categories;
          _movieCatsReady = true;
        case 'series':
          _seriesCats = categories;
          _seriesCatsReady = true;
        case 'live':
          _liveCats = categories;
          _liveCatsReady = true;
      }
      // Dedicated browse pages open on a focused category instead of issuing
      // an expensive whole-catalog request. “All categories” remains selectable.
      if (_browse &&
          _section == section &&
          widget.initialCategory == null &&
          _cat == 'all' &&
          categories.isNotEmpty) {
        _cat = categories.first.id;
      }
    });
  }

  void _onRefresh() {
    if (!mounted) return;
    setState(() {
      _clearResults();
      _movieCatsReady = false;
      _seriesCatsReady = false;
      _liveCatsReady = false;
      _cat = widget.initialCategory ?? 'all';
    });
    _loadCats();
  }

  @override
  void dispose() {
    contentRefresh.removeListener(_onRefresh);
    CatalogCache.instance.revision.removeListener(_onCatalogRevision);
    _ctrl.dispose();
    _searchFocus.dispose();
    for (final node in _sectionFocus) {
      node.dispose();
    }
    _categoryButtonFocus
      ..removeListener(_onSortFocusChanged)
      ..dispose();
    _sortFocus
      ..removeListener(_onSortFocusChanged)
      ..dispose();
    _gridScroll.dispose();
    _categoryScope.dispose();
    _gridScope.dispose();
    _categorySelectionTimer?.cancel();
    _queryTimer?.cancel();
    for (final node in _gridFocus) {
      node.dispose();
    }
    for (final node in _categoryFocus.values) {
      node.dispose();
    }
    for (final nodes in _searchResultFocus.values) {
      for (final node in nodes) {
        node.dispose();
      }
    }
    for (final controller in _searchShelfScroll.values) {
      controller.dispose();
    }
    super.dispose();
  }

  String _categoryFocusKey(String id) => '$_section:$id';

  FocusNode _categoryFocusNode(String id) => _categoryFocus.putIfAbsent(
    _categoryFocusKey(id),
    () => FocusNode(debugLabel: '$_section category $id'),
  );

  void _onSortFocusChanged() {
    if (mounted) setState(() {});
  }

  void _requestVisibleCategoryFocus() {
    _categorySelectionTimer?.cancel();
    final visibleIds = <String>{'all', for (final c in _curCats) c.id};
    final id = visibleIds.contains(_cat) ? _cat : 'all';
    final node = _categoryFocusNode(id);

    void attempt(int remainingFrames) {
      if (!mounted) return;
      if (node.context != null && node.canRequestFocus) {
        node.requestFocus();
        return;
      }
      if (remainingFrames > 0) {
        WidgetsBinding.instance.addPostFrameCallback(
          (_) => attempt(remainingFrames - 1),
        );
      }
    }

    attempt(6);
  }

  int get _sectionFocusIndex => switch (_section) {
    'movie' => 1,
    'series' => 2,
    'live' => 3,
    _ => 0,
  };

  bool _isDirectionalKeyEvent(KeyEvent event) =>
      event is KeyDownEvent || event is KeyRepeatEvent;

  KeyEventResult _moveSearchFieldFocus(FocusNode _, KeyEvent event) {
    if (!_isDirectionalKeyEvent(event)) return KeyEventResult.ignored;
    if (event.logicalKey == LogicalKeyboardKey.select ||
        event.logicalKey == LogicalKeyboardKey.gameButtonA) {
      _showSearchKeyboard();
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.arrowDown) {
      _sectionFocus[_sectionFocusIndex].requestFocus();
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.arrowUp) {
      final top = widget.shellTopFocusNode;
      if (top != null && top.canRequestFocus) top.requestFocus();
      return KeyEventResult.handled;
    }
    // Left and Right remain text-cursor commands while editing.
    return KeyEventResult.ignored;
  }

  KeyEventResult _moveSectionFocus(int index, KeyEvent event) {
    if (!_isDirectionalKeyEvent(event)) return KeyEventResult.ignored;
    final key = event.logicalKey;
    if (key == LogicalKeyboardKey.arrowUp) {
      _searchFocus.requestFocus();
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowDown) {
      return _focusResultsFromControls();
    }
    if (key == LogicalKeyboardKey.arrowLeft) {
      if (index > 0) {
        _sectionFocus[index - 1].requestFocus();
      } else {
        widget.shellRailFocusNode?.requestFocus();
      }
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowRight) {
      if (index + 1 < _sectionFocus.length) {
        _sectionFocus[index + 1].requestFocus();
      } else if (_section != 'all') {
        _categoryButtonFocus.requestFocus();
      }
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  KeyEventResult _moveCategoryButtonFocus(FocusNode _, KeyEvent event) {
    if (!_isDirectionalKeyEvent(event)) return KeyEventResult.ignored;
    final key = event.logicalKey;
    if (key == LogicalKeyboardKey.arrowUp) {
      _searchFocus.requestFocus();
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowLeft) {
      _sectionFocus[_sectionFocusIndex].requestFocus();
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowRight) {
      _sortFocus.requestFocus();
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowDown) {
      return _focusResultsFromControls();
    }
    return KeyEventResult.ignored;
  }

  KeyEventResult _focusResultsFromControls() {
    if (_section != 'all') {
      _requestGridFocus(_lastGridIndex);
      return KeyEventResult.handled;
    }
    if (_q.trim().isEmpty) return KeyEventResult.handled;
    _requestSearchResultFocus(0, 0);
    return KeyEventResult.handled;
  }

  KeyEventResult _moveSortFocus(FocusNode _, KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    if (event.logicalKey == LogicalKeyboardKey.arrowDown) {
      _requestGridFocus(_lastGridIndex);
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.arrowLeft) {
      if (_browse) {
        _requestVisibleCategoryFocus();
      } else {
        _categoryButtonFocus.requestFocus();
      }
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.arrowUp) {
      if (_browse) {
        final top = widget.shellTopFocusNode;
        if (top != null && top.canRequestFocus) top.requestFocus();
      } else {
        _searchFocus.requestFocus();
      }
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.arrowRight) {
      // Sort is the top-right edge of the catalog. Keep focus visible instead
      // of allowing the geometry policy to lose it outside the page.
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  void _ensureSearchResultFocusNodes(String group, int count) {
    final nodes = _searchResultFocus.putIfAbsent(group, () => <FocusNode>[]);
    _searchResultCounts[group] = count;
    while (nodes.length < count) {
      nodes.add(FocusNode(debugLabel: 'Search $group result ${nodes.length}'));
    }
    _searchShelfScroll.putIfAbsent(group, ScrollController.new);
  }

  void _requestSearchResultFocus(int requestedGroup, int requestedIndex) {
    final serial = ++_searchFocusRequestSerial;
    if (_visibleSearchGroups.isEmpty) {
      _pendingSearchFocus = (requestedGroup, requestedIndex);
      return;
    }
    final groupIndex = requestedGroup
        .clamp(0, _visibleSearchGroups.length - 1)
        .toInt();
    final group = _visibleSearchGroups[groupIndex];
    final nodes = _searchResultFocus[group] ?? const <FocusNode>[];
    final count = _searchResultCounts[group] ?? 0;
    if (nodes.isEmpty || count == 0) {
      _pendingSearchFocus = (groupIndex, requestedIndex);
      return;
    }
    final index = requestedIndex.clamp(0, count - 1).toInt();
    _pendingSearchFocus = (groupIndex, index);

    void attempt(int remainingFrames) {
      if (!mounted || serial != _searchFocusRequestSerial) return;
      final node = nodes[index];
      if (node.context != null && node.canRequestFocus) {
        _pendingSearchFocus = null;
        node.requestFocus();
        return;
      }
      final controller = _searchShelfScroll[group];
      if (controller?.hasClients ?? false) {
        final desired = (index * (kPosterW + 14) - kPosterW).clamp(
          controller!.position.minScrollExtent,
          controller.position.maxScrollExtent,
        );
        controller.jumpTo(desired.toDouble());
      }
      if (remainingFrames > 0) {
        WidgetsBinding.instance.addPostFrameCallback(
          (_) => attempt(remainingFrames - 1),
        );
      }
    }

    attempt(8);
  }

  void _resumePendingSearchFocus() {
    final pending = _pendingSearchFocus;
    if (pending == null || _visibleSearchGroups.isEmpty) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _pendingSearchFocus == pending) {
        _requestSearchResultFocus(pending.$1, pending.$2);
      }
    });
  }

  KeyEventResult _moveSearchResultFocus(
    String group,
    int index,
    KeyEvent event,
  ) {
    if (!_isDirectionalKeyEvent(event)) return KeyEventResult.ignored;
    final groupIndex = _visibleSearchGroups.indexOf(group);
    if (groupIndex < 0) return KeyEventResult.handled;
    final key = event.logicalKey;
    if (key == LogicalKeyboardKey.arrowLeft) {
      if (index > 0) {
        _requestSearchResultFocus(groupIndex, index - 1);
      } else {
        widget.shellRailFocusNode?.requestFocus();
      }
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowRight) {
      final count = _searchResultCounts[group] ?? 0;
      if (index + 1 < count) {
        _requestSearchResultFocus(groupIndex, index + 1);
      }
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowUp) {
      if (groupIndex == 0) {
        _sectionFocus[_sectionFocusIndex].requestFocus();
      } else {
        _requestSearchResultFocus(groupIndex - 1, index);
      }
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowDown) {
      if (groupIndex + 1 < _visibleSearchGroups.length) {
        _requestSearchResultFocus(groupIndex + 1, index);
      }
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  void _selectCategory(String id, {bool restoreCategoryFocus = true}) {
    _categorySelectionTimer?.cancel();
    if (_cat == id) return;
    final node = _categoryFocusNode(id);
    _lastGridIndex = 0;
    // Results are cached per category. Clearing every category here made TV
    // browsing refetch data whenever focus crossed the sidebar and was the main
    // source of visible hangs. Only switch the active cache key.
    setState(() => _cat = id);
    if (!restoreCategoryFocus) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && node.canRequestFocus) node.requestFocus();
    });
  }

  void _selectCategoryAfterFocusSettles(String id) {
    _categorySelectionTimer?.cancel();
    final node = _categoryFocusNode(id);
    final delay = DeviceProfile.isTelevision
        ? const Duration(milliseconds: 220)
        : const Duration(milliseconds: 70);
    _categorySelectionTimer = Timer(delay, () {
      if (!mounted || !node.hasFocus) return;
      _selectCategory(id);
    });
  }

  KeyEventResult _moveCategoryFocus(
    List<(String, String)> categories,
    int index,
    KeyEvent event,
  ) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    if (event.logicalKey == LogicalKeyboardKey.arrowLeft) {
      _categorySelectionTimer?.cancel();
      final railNode = widget.shellRailFocusNode;
      if (railNode != null && railNode.canRequestFocus) {
        railNode.requestFocus();
        return KeyEventResult.handled;
      }
      return FocusManager.instance.primaryFocus?.focusInDirection(
                TraversalDirection.left,
              ) ==
              true
          ? KeyEventResult.handled
          : KeyEventResult.ignored;
    }
    if (event.logicalKey == LogicalKeyboardKey.arrowRight) {
      final id = categories[index].$1;
      if (_cat != id) {
        _selectCategory(id, restoreCategoryFocus: false);
      }
      _requestGridFocus(_lastGridIndex);
      return KeyEventResult.handled;
    }
    final delta = event.logicalKey == LogicalKeyboardKey.arrowUp
        ? -1
        : event.logicalKey == LogicalKeyboardKey.arrowDown
        ? 1
        : 0;
    if (delta == 0) return KeyEventResult.ignored;
    final target = index + delta;
    // Vertical movement is contained inside the category zone. Letting an edge
    // event fall through makes the geometry policy choose a content tile.
    if (target < 0) {
      _sortFocus.requestFocus();
      return KeyEventResult.handled;
    }
    if (target >= categories.length) return KeyEventResult.handled;
    _categoryFocusNode(categories[target].$1).requestFocus();
    return KeyEventResult.handled;
  }

  void _ensureGridFocusNodes(int count) {
    while (_gridFocus.length < count) {
      _gridFocus.add(
        FocusNode(debugLabel: 'Catalog tile ${_gridFocus.length}'),
      );
    }
  }

  void _resumePendingGridFocus() {
    if (_pendingGridFocus == null || _gridFocusResumeScheduled) return;
    _gridFocusResumeScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _gridFocusResumeScheduled = false;
      final target = _pendingGridFocus;
      if (mounted && target != null) _requestGridFocus(target);
    });
  }

  void _requestGridFocus(int requestedIndex) {
    final requestSerial = ++_gridFocusRequestSerial;
    if (_gridFocus.isEmpty || (_browse && !_has(_section, _cat))) {
      _pendingGridFocus = requestedIndex;
      return;
    }
    final target = requestedIndex.clamp(0, _gridFocus.length - 1).toInt();
    _pendingGridFocus = target;

    void attempt(int remainingFrames) {
      if (!mounted || requestSerial != _gridFocusRequestSerial) return;
      final node = _gridFocus[target];
      if (node.context != null && node.canRequestFocus) {
        _pendingGridFocus = null;
        node.requestFocus();
        return;
      }
      if (_gridScroll.hasClients && _gridScroll.position.hasContentDimensions) {
        final row = target ~/ _gridColumns;
        final desired = (row * _gridRowExtent - _gridRowExtent).clamp(
          _gridScroll.position.minScrollExtent,
          _gridScroll.position.maxScrollExtent,
        );
        if ((_gridScroll.offset - desired).abs() > 1) {
          _gridScroll.jumpTo(desired);
        }
      }
      if (remainingFrames > 0) {
        WidgetsBinding.instance.addPostFrameCallback(
          (_) => attempt(remainingFrames - 1),
        );
      }
    }

    attempt(10);
  }

  KeyEventResult _moveGridFocus(
    int index,
    KeyEvent event, {
    required int itemCount,
    required int columns,
    required double rowExtent,
  }) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    final key = event.logicalKey;
    final column = index % columns;
    int? target;
    if (key == LogicalKeyboardKey.arrowRight) {
      // Stay inside the grid at a row edge rather than allowing Flutter to
      // jump to an unrelated sidebar/header control.
      if (column == columns - 1 || index + 1 >= itemCount) {
        return KeyEventResult.handled;
      }
      target = index + 1;
    } else if (key == LogicalKeyboardKey.arrowLeft) {
      if (column == 0) {
        _requestVisibleCategoryFocus();
        return KeyEventResult.handled;
      }
      target = index - 1;
    } else if (key == LogicalKeyboardKey.arrowDown) {
      if (index + columns >= itemCount) return KeyEventResult.handled;
      target = index + columns;
    } else if (key == LogicalKeyboardKey.arrowUp) {
      // Sort is the only deliberate exit above the first content row. This
      // avoids the old diagonal category jump while keeping the top-right
      // catalog action reachable from every column.
      if (index < columns) {
        _sortFocus.requestFocus();
        return KeyEventResult.handled;
      }
      target = index - columns;
    } else {
      return KeyEventResult.ignored;
    }

    _gridColumns = columns;
    _gridRowExtent = rowExtent;
    _requestGridFocus(target);
    return KeyEventResult.handled;
  }

  void _onCatalogRevision() {
    if (!mounted) return;
    setState(_clearResults);
    _loadCats();
  }

  void focusSearch() {
    _showSearchKeyboard();
  }

  void _showSearchKeyboard() {
    _searchFocus.requestFocus();
    if (!DeviceProfile.isTelevision) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_searchFocus.hasFocus) return;
      unawaited(SystemChannels.textInput.invokeMethod<void>('TextInput.show'));
    });
  }

  String get _resultSignature => '${_q.trim()}\u0000$_sort';

  bool _has(String section, String cat) {
    final contains = switch (section) {
      'movie' => _movieByCat.containsKey(cat),
      'series' => _seriesByCat.containsKey(cat),
      _ => _liveByCat.containsKey(cat),
    };
    return contains &&
        _cacheSignatures[_pageKey(section, cat)] == _resultSignature;
  }

  String _pageKey(String section, String cat) => '$section:$cat';

  void _clearResults() {
    _resultGeneration++;
    _movieByCat.clear();
    _seriesByCat.clear();
    _liveByCat.clear();
    _hasMore.clear();
    _cacheSignatures.clear();
    _inFlight.clear();
  }

  void _changeResults(VoidCallback change) {
    setState(() {
      change();
      // Keep category/section pages in memory and invalidate only in-flight
      // work. Each page is tagged with its query/sort signature, so stale data
      // is never displayed but revisiting an unchanged tab is instant.
      _resultGeneration++;
      _inFlight.clear();
    });
  }

  void _selectSection(String section) {
    if (_section == section) return;
    setState(() {
      _section = section;
      _cat = 'all';
      _sort = 'default';
      _lastGridIndex = 0;
    });
  }

  void _onQueryChanged(String value) {
    _queryTimer?.cancel();
    final delay = DeviceProfile.isTelevision
        ? const Duration(milliseconds: 320)
        : const Duration(milliseconds: 220);
    _queryTimer = Timer(delay, () {
      if (mounted && value != _q) _changeResults(() => _q = value);
    });
  }

  void _onQuerySubmitted(String value) {
    _queryTimer?.cancel();
    if (value != _q) _changeResults(() => _q = value);
  }

  /// Ensure the first page for (section, category) is loaded. Safe from build.
  void _ensure(String section, String cat) {
    if (_has(section, cat)) return;
    _loadNext(section, cat);
  }

  void _loadNext(String section, String cat) {
    final pageKey = _pageKey(section, cat);
    final signature = _resultSignature;
    if (_has(section, cat) && !(_hasMore[pageKey] ?? false)) return;
    final generation = _resultGeneration;
    final requestKey = '$generation:$pageKey';
    if (_inFlight.contains(requestKey)) return;
    _inFlight.add(requestKey);
    final offset = !_has(section, cat)
        ? 0
        : switch (section) {
            'movie' => _movieByCat[cat]?.length ?? 0,
            'series' => _seriesByCat[cat]?.length ?? 0,
            _ => _liveByCat[cat]?.length ?? 0,
          };

    Future<void> finish(Future<void> Function() run) => run()
        .catchError(
          (_) => _storePage(
            section,
            cat,
            const [],
            false,
            generation,
            offset,
            signature,
          ),
        )
        .whenComplete(() => _inFlight.remove(requestKey));

    final categoryId = cat == 'all' ? null : cat;
    switch (section) {
      case 'movie':
        finish(
          () => CatalogCache.instance
              .vodPage(
                widget.client,
                categoryId: categoryId,
                offset: offset,
                limit: _pageSize,
                query: _q.trim(),
                sort: _sort,
              )
              .then(
                (page) => _storePage(
                  section,
                  cat,
                  page.items,
                  page.hasMore,
                  generation,
                  offset,
                  signature,
                ),
              ),
        );
      case 'series':
        finish(
          () => CatalogCache.instance
              .seriesPage(
                widget.client,
                categoryId: categoryId,
                offset: offset,
                limit: _pageSize,
                query: _q.trim(),
                sort: _sort,
              )
              .then(
                (page) => _storePage(
                  section,
                  cat,
                  page.items,
                  page.hasMore,
                  generation,
                  offset,
                  signature,
                ),
              ),
        );
      default:
        finish(
          () => CatalogCache.instance
              .livePage(
                widget.client,
                categoryId: categoryId,
                offset: offset,
                limit: _pageSize,
                query: _q.trim(),
                sort: _sort,
              )
              .then(
                (page) => _storePage(
                  section,
                  cat,
                  page.items,
                  page.hasMore,
                  generation,
                  offset,
                  signature,
                ),
              ),
        );
    }
  }

  void _storePage(
    String section,
    String cat,
    List<dynamic> values,
    bool hasMore,
    int generation,
    int offset,
    String signature,
  ) {
    if (!mounted || generation != _resultGeneration) return;
    setState(() {
      switch (section) {
        case 'movie':
          _movieByCat[cat] = [
            if (offset > 0) ...?_movieByCat[cat],
            ...values.cast<VodStream>(),
          ];
        case 'series':
          _seriesByCat[cat] = [
            if (offset > 0) ...?_seriesByCat[cat],
            ...values.cast<Series>(),
          ];
        default:
          _liveByCat[cat] = [
            if (offset > 0) ...?_liveByCat[cat],
            ...values.cast<LiveStream>(),
          ];
      }
      _hasMore[_pageKey(section, cat)] = hasMore;
      _cacheSignatures[_pageKey(section, cat)] = signature;
    });
  }

  // builders → result items
  _Res _movie(VodStream m) => _Res(
    m.name,
    m.icon,
    m.rating,
    _year(m.name),
    false,
    () => _push(MovieDetailScreen(client: widget.client, movie: m)),
  );
  _Res _ser(Series s) => _Res(
    s.name,
    s.cover,
    s.rating,
    _year(s.releaseDate.isEmpty ? s.name : s.releaseDate),
    false,
    () => _push(
      SeriesDetailScreen(
        client: widget.client,
        seriesId: s.seriesId,
        title: s.name,
        preview: s,
      ),
    ),
  );
  PlayerItem _liveItem(LiveStream s) {
    final url = widget.client.streamUrl('live', s.streamId, ext: 'ts');
    return PlayerItem(
      url,
      s.name,
      isLive: true,
      poster: s.icon,
      httpHeaders: widget.client.streamHeaders(s.streamId),
      favRef: MediaRef(
        kind: 'live',
        id: s.streamId,
        name: s.name,
        image: s.icon,
        url: url,
      ),
      epg: () => widget.client.shortEpg(s.streamId),
    );
  }

  void _push(Widget w) =>
      Navigator.of(context).push(MaterialPageRoute(builder: (_) => w));

  List<Category> get _curCats => switch (_section) {
    'movie' => _movieCats,
    'series' => _seriesCats,
    'live' => _liveCats,
    _ => const [],
  };

  bool get _curCatsReady => switch (_section) {
    'movie' => _movieCatsReady,
    'series' => _seriesCatsReady,
    'live' => _liveCatsReady,
    _ => true,
  };

  String get _catLabel {
    if (_cat == 'all') return 'All categories';
    return _curCats
        .firstWhere(
          (c) => c.id == _cat,
          orElse: () => Category('all', 'All categories'),
        )
        .name;
  }

  // Dedicated browse mode (Movies / Series / Live sidebar entries): a titled
  // catalog page — no search bar or section chips, just category + sort + grid.
  bool get _browse => widget.initialSection != null;
  String get _sectionTitle => switch (_section) {
    'movie' => 'Movies',
    'series' => 'Series',
    'live' => 'Live TV',
    _ => 'Browse',
  };

  @override
  Widget build(BuildContext context) {
    super.build(context);
    // Self-contained Scaffold so it renders correctly whether it's a shell tab
    // or pushed as a route (e.g. Home's "See all") — otherwise text loses its
    // theme (red/yellow unstyled rendering) with no Material ancestor.
    final canBack = Navigator.of(context).canPop();
    final wide = isWide(context);
    final body = _browse
        ? Column(
            children: [
              const SizedBox(height: 10),
              _browseHeader(canBack),
              const SizedBox(height: 12),
              if (wide)
                Expanded(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _catSidebar(),
                      Expanded(child: _body()),
                    ],
                  ),
                )
              else ...[
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: _catButton(),
                ),
                const SizedBox(height: 8),
                Expanded(child: _body()),
              ],
            ],
          )
        : Column(
            children: [
              const SizedBox(height: 8),
              _searchControls(),
              const SizedBox(height: 8),
              Expanded(child: _body()),
            ],
          );
    return Scaffold(
      backgroundColor: canBack ? bg : Colors.transparent,
      body: SafeArea(top: canBack, bottom: false, child: body),
    );
  }

  Widget _browseHeader(bool canBack) {
    return Padding(
      padding: EdgeInsets.fromLTRB(canBack ? 4 : 18, 8, 16, 0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          if (canBack)
            Padding(
              padding: const EdgeInsets.only(right: 2),
              child: IconButton(
                autofocus: true,
                onPressed: () => Navigator.of(context).pop(),
                icon: Icon(Icons.arrow_back_rounded, color: textHi),
              ),
            ),
          Expanded(
            child: Row(
              children: [
                Flexible(
                  child: Text(
                    widget.initialCategoryName ?? _sectionTitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 30,
                      fontWeight: FontWeight.w800,
                      letterSpacing: -0.6,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Icon(
                  _section == 'movie'
                      ? Icons.movie_rounded
                      : _section == 'series'
                      ? Icons.video_library_rounded
                      : Icons.live_tv_rounded,
                  color: accentInk,
                  size: 24,
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          _sortButton(),
        ],
      ),
    );
  }

  // ---- pieces ----
  Widget _searchField() => SearchField(
    hint: 'Search movies, series, channels…',
    controller: _ctrl,
    focusNode: _searchFocus,
    onChanged: _onQueryChanged,
    onSubmitted: _onQuerySubmitted,
    trailing: _q.isNotEmpty
        ? RemoteTap(
            semanticLabel: 'Clear search',
            focusRadius: 18,
            onTap: () => _changeResults(() {
              _queryTimer?.cancel();
              _q = '';
              _ctrl.clear();
              _searchFocus.requestFocus();
            }),
            child: Padding(
              padding: const EdgeInsets.all(8),
              child: Icon(Icons.close_rounded, color: subtle, size: 20),
            ),
          )
        : null,
  );

  Widget _searchControls() {
    return LayoutBuilder(
      builder: (context, constraints) {
        final filters = _section != 'all';
        final roomy = constraints.maxWidth >= 1180;
        final medium = constraints.maxWidth >= 720;

        if (roomy) {
          return Padding(
            padding: const EdgeInsets.symmetric(horizontal: 18),
            child: Row(
              children: [
                Expanded(child: _searchField()),
                const SizedBox(width: 14),
                SizedBox(width: 332, child: _sectionChips()),
                if (filters) ...[
                  const SizedBox(width: 12),
                  SizedBox(width: 220, child: _catButton()),
                  const SizedBox(width: 8),
                  _sortButton(),
                ],
              ],
            ),
          );
        }

        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Column(
            children: [
              _searchField(),
              const SizedBox(height: 10),
              if (medium)
                Row(
                  children: [
                    Expanded(child: _sectionChips()),
                    if (filters) ...[
                      const SizedBox(width: 10),
                      SizedBox(width: 220, child: _catButton()),
                      const SizedBox(width: 8),
                      _sortButton(),
                    ],
                  ],
                )
              else ...[
                _sectionChips(),
                if (filters) ...[
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(child: _catButton()),
                      const SizedBox(width: 8),
                      _sortButton(),
                    ],
                  ),
                ],
              ],
            ],
          ),
        );
      },
    );
  }

  Widget _sectionChips() {
    const items = [
      (id: 'all', label: 'All'),
      (id: 'movie', label: 'Movies'),
      (id: 'series', label: 'Series'),
      (id: 'live', label: 'Live'),
    ];
    return SizedBox(
      height: 36,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: EdgeInsets.zero,
        shrinkWrap: true,
        itemCount: items.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (_, i) {
          final sel = _section == items[i].id;
          return RemoteTap(
            focusNode: _sectionFocus[i],
            onKeyEvent: (_, event) => _moveSectionFocus(i, event),
            onFocusChange: (focused) {
              if (focused && !sel) {
                _selectSection(items[i].id);
              }
            },
            onTap: () => _selectSection(items[i].id),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              alignment: Alignment.center,
              padding: const EdgeInsets.symmetric(horizontal: 18),
              decoration: BoxDecoration(
                color: sel ? accent : surfaceHi.withValues(alpha: 0.5),
                borderRadius: BorderRadius.circular(13),
                border: Border.all(color: sel ? Colors.transparent : line),
              ),
              child: Text(
                items[i].label,
                style: TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 13,
                  color: sel ? onAccent : muted,
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  static const _sortLabels = {
    'default': 'Default',
    'az': 'A–Z',
    'za': 'Z–A',
    'rating': 'Top rated',
    'recent': 'Recently added',
    'year': 'Newest',
  };

  // Sort → an anchored dropdown menu (not a bottom sheet).
  Widget _sortButton() {
    final entries = _sortLabels.entries
        .where(
          (e) =>
              !(_section == 'live' &&
                  (e.key == 'rating' || e.key == 'recent' || e.key == 'year')),
        )
        .toList();
    return FocusableActionDetector(
      focusNode: _sortFocus,
      shortcuts: const <ShortcutActivator, Intent>{
        SingleActivator(LogicalKeyboardKey.enter): ActivateIntent(),
        SingleActivator(LogicalKeyboardKey.numpadEnter): ActivateIntent(),
        SingleActivator(LogicalKeyboardKey.select): ActivateIntent(),
        SingleActivator(LogicalKeyboardKey.accept): ActivateIntent(),
        SingleActivator(LogicalKeyboardKey.execute): ActivateIntent(),
        SingleActivator(LogicalKeyboardKey.gameButtonA): ActivateIntent(),
      },
      actions: <Type, Action<Intent>>{
        ActivateIntent: CallbackAction<ActivateIntent>(
          onInvoke: (_) {
            _sortMenuKey.currentState?.showButtonMenu();
            return null;
          },
        ),
      },
      child: ExcludeFocus(
        child: PopupMenuButton<String>(
          key: _sortMenuKey,
          tooltip: 'Sort',
          color: surface,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: BorderSide(color: line),
          ),
          onSelected: (v) => _changeResults(() => _sort = v),
          itemBuilder: (_) => [
            for (final e in entries)
              PopupMenuItem(
                value: e.key,
                child: Row(
                  children: [
                    Icon(
                      _sort == e.key ? Icons.check_rounded : Icons.sort_rounded,
                      color: _sort == e.key ? accentInk : muted,
                      size: 18,
                    ),
                    const SizedBox(width: 10),
                    Text(
                      e.value,
                      style: TextStyle(
                        fontWeight: _sort == e.key
                            ? FontWeight.w800
                            : FontWeight.w600,
                        color: textHi,
                      ),
                    ),
                  ],
                ),
              ),
          ],
          child: AnimatedScale(
            scale: _sortFocus.hasFocus ? 1.045 : 1,
            duration: const Duration(milliseconds: 130),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 130),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
              decoration: BoxDecoration(
                color: _sortFocus.hasFocus
                    ? accent.withValues(alpha: .22)
                    : surfaceHi.withValues(alpha: 0.6),
                borderRadius: BorderRadius.circular(13),
                border: Border.all(
                  color: _sortFocus.hasFocus ? accentInk : line,
                  width: _sortFocus.hasFocus ? 3 : 1,
                ),
                boxShadow: _sortFocus.hasFocus
                    ? glow(accent, blur: 18, a: .5)
                    : null,
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.swap_vert_rounded,
                    size: 18,
                    color: _sort == 'default' ? muted : accentInk,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    _sort == 'default' ? 'Sort' : _sortLabels[_sort]!,
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 13,
                      color: _sort == 'default' ? textHi : accentInk,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  // Category → anchored dropdown (used on mobile / search mode). No bottom sheet.
  Widget _catButton() {
    return FocusableActionDetector(
      focusNode: _categoryButtonFocus,
      shortcuts: const <ShortcutActivator, Intent>{
        SingleActivator(LogicalKeyboardKey.enter): ActivateIntent(),
        SingleActivator(LogicalKeyboardKey.numpadEnter): ActivateIntent(),
        SingleActivator(LogicalKeyboardKey.select): ActivateIntent(),
        SingleActivator(LogicalKeyboardKey.accept): ActivateIntent(),
        SingleActivator(LogicalKeyboardKey.execute): ActivateIntent(),
        SingleActivator(LogicalKeyboardKey.gameButtonA): ActivateIntent(),
      },
      actions: <Type, Action<Intent>>{
        ActivateIntent: CallbackAction<ActivateIntent>(
          onInvoke: (_) {
            _categoryMenuKey.currentState?.showButtonMenu();
            return null;
          },
        ),
      },
      child: ExcludeFocus(
        child: PopupMenuButton<String>(
          key: _categoryMenuKey,
          tooltip: 'Category',
          color: surface,
          constraints: const BoxConstraints(minWidth: 260, maxHeight: 460),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: BorderSide(color: line),
          ),
          onSelected: (v) => _selectCategory(v, restoreCategoryFocus: false),
          itemBuilder: (_) => [
            _catItem('all', 'All categories'),
            for (final c in _curCats) _catItem(c.id, c.name),
          ],
          child: AnimatedScale(
            scale: _categoryButtonFocus.hasFocus ? 1.035 : 1,
            duration: const Duration(milliseconds: 130),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              decoration: BoxDecoration(
                color: _categoryButtonFocus.hasFocus
                    ? accent.withValues(alpha: .22)
                    : surfaceHi.withValues(alpha: 0.6),
                borderRadius: BorderRadius.circular(13),
                border: Border.all(
                  color: _categoryButtonFocus.hasFocus ? accentInk : line,
                  width: _categoryButtonFocus.hasFocus ? 3 : 1,
                ),
                boxShadow: _categoryButtonFocus.hasFocus
                    ? glow(accent, blur: 18, a: .5)
                    : null,
              ),
              child: Row(
                children: [
                  Icon(Icons.category_rounded, size: 18, color: accentInk),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _catLabel,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 13,
                      ),
                    ),
                  ),
                  Icon(Icons.expand_more_rounded, color: muted, size: 20),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  PopupMenuItem<String> _catItem(String id, String name) {
    final sel = _cat == id;
    return PopupMenuItem(
      value: id,
      child: Row(
        children: [
          if (sel)
            Icon(Icons.check_rounded, color: accentInk, size: 18)
          else
            const SizedBox(width: 18),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontWeight: sel ? FontWeight.w800 : FontWeight.w600,
                color: sel ? textHi : muted,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // Desktop browse: a persistent category list beside the grid (no sheet).
  Widget _catSidebar() {
    final cats = <(String, String)>[
      ('all', 'All categories'),
      for (final c in _curCats) (c.id, c.name),
    ];
    return FocusScope(
      node: _categoryScope,
      child: FocusTraversalGroup(
        policy: WidgetOrderTraversalPolicy(),
        child: Container(
          width: 240,
          decoration: BoxDecoration(
            border: Border(right: BorderSide(color: line)),
          ),
          child: ListView(
            padding: const EdgeInsets.fromLTRB(12, 2, 12, 24),
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 6, 12, 10),
                child: Text('CATEGORIES', style: kSection()),
              ),
              for (var i = 0; i < cats.length; i++)
                _catTile(
                  cats[i].$1,
                  cats[i].$2,
                  onKeyEvent: (_, event) => _moveCategoryFocus(cats, i, event),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _catTile(
    String id,
    String name, {
    FocusOnKeyEventCallback? onKeyEvent,
  }) {
    final sel = _cat == id;
    return FocusableTap(
      focusNode: _categoryFocusNode(id),
      onKeyEvent: onKeyEvent,
      onFocusChange: (focused) {
        if (focused && !sel) _selectCategoryAfterFocusSettles(id);
      },
      onTap: () => _selectCategory(id),
      builder: (context, active) => AnimatedContainer(
        duration: const Duration(milliseconds: 140),
        margin: const EdgeInsets.symmetric(vertical: 2),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        decoration: BoxDecoration(
          color: sel
              ? accent.withValues(alpha: 0.16)
              : (active
                    ? surfaceHi.withValues(alpha: 0.7)
                    : Colors.transparent),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            AnimatedContainer(
              duration: const Duration(milliseconds: 140),
              width: 3,
              height: sel ? 16 : 0,
              decoration: BoxDecoration(
                color: accentInk,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontWeight: sel ? FontWeight.w800 : FontWeight.w600,
                  fontSize: 14,
                  color: sel ? textHi : muted,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _body() {
    final q = _q.trim();

    if (_section == 'all') {
      if (q.isEmpty) {
        _visibleSearchGroups = const [];
        return _prompt();
      }
      // Each media type queries only its first matching page. Providers that
      // lack a whole-catalog endpoint are imported into SQLite once, then all
      // subsequent searches stay local and paged.
      _ensure('movie', 'all');
      _ensure('series', 'all');
      _ensure('live', 'all');
      final movies = _has('movie', 'all') ? _movieByCat['all'] : null;
      final series = _has('series', 'all') ? _seriesByCat['all'] : null;
      final live = _has('live', 'all') ? _liveByCat['all'] : null;
      final loading = movies == null || series == null || live == null;
      final mr = (movies ?? []).take(18).map(_movie).toList();
      final sr = (series ?? []).take(18).map(_ser).toList();
      final liveResults = (live ?? []).take(18).toList();
      final livePlaylist = liveResults.map(_liveItem).toList();
      final lr = liveResults
          .asMap()
          .entries
          .map(
            (entry) => _Res(
              entry.value.name,
              entry.value.icon,
              0,
              '',
              true,
              () => PlaybackController.instance.open(livePlaylist, entry.key),
            ),
          )
          .toList();
      if (loading && mr.isEmpty && sr.isEmpty && lr.isEmpty) {
        _visibleSearchGroups = const [];
        return const GridLoading();
      }
      if (mr.isEmpty && sr.isEmpty && lr.isEmpty) {
        _visibleSearchGroups = const [];
        return _empty('No results for “$_q”.');
      }
      final groups = <({String id, String title, List<_Res> items})>[
        if (mr.isNotEmpty) (id: 'movie', title: 'Movies', items: mr),
        if (sr.isNotEmpty) (id: 'series', title: 'Series', items: sr),
        if (lr.isNotEmpty) (id: 'live', title: 'Channels', items: lr),
      ];
      _visibleSearchGroups = [for (final group in groups) group.id];
      for (final group in groups) {
        _ensureSearchResultFocusNodes(group.id, group.items.length);
      }
      _resumePendingSearchFocus();
      return ListView(
        padding: const EdgeInsets.only(top: 8, bottom: 120),
        children: [
          for (final group in groups)
            _group(group.id, group.title, group.items),
        ],
      );
    }

    // specific section — fetch the selected category directly
    _visibleSearchGroups = const [];
    final live = _section == 'live';
    if (_browse && !_curCatsReady) return GridLoading(channel: live);
    final catId = _cat;
    _ensure(_section, catId);
    final loaded = _has(_section, catId);
    final pageKey = _pageKey(_section, catId);
    List<_Res> items;
    if (_section == 'movie') {
      items = (_movieByCat[catId] ?? const []).map(_movie).toList();
    } else if (_section == 'series') {
      items = (_seriesByCat[catId] ?? const []).map(_ser).toList();
    } else {
      // build a shared channel playlist so the player can zap next/previous
      final chans = _liveByCat[catId] ?? const <LiveStream>[];
      final pl = chans.map(_liveItem).toList();
      items = chans
          .asMap()
          .entries
          .map(
            (e) => _Res(
              e.value.name,
              e.value.icon,
              0,
              '',
              true,
              () => PlaybackController.instance.open(pl, e.key),
            ),
          )
          .toList();
    }

    if (!loaded) return GridLoading(channel: live);
    if (items.isEmpty) {
      return _empty(q.isEmpty ? 'Nothing here.' : 'No results for “$_q”.');
    }

    final more = _hasMore[pageKey] ?? false;
    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = gridColumns(
          constraints.maxWidth,
          tile: live ? 150 : 136,
        );
        final tileWidth =
            (constraints.maxWidth - 32 - ((columns - 1) * 13)) / columns;
        final rowExtent = tileWidth / (live ? 0.76 : 0.66) + 20;
        _gridColumns = columns;
        _gridRowExtent = rowExtent;
        _ensureGridFocusNodes(items.length);
        _resumePendingGridFocus();
        return NotificationListener<ScrollNotification>(
          onNotification: (notification) {
            if (more && notification.metrics.extentAfter < 900) {
              _loadNext(_section, catId);
            }
            return false;
          },
          child: FocusScope(
            node: _gridScope,
            child: FocusTraversalGroup(
              policy: WidgetOrderTraversalPolicy(),
              child: GridView.builder(
                controller: _gridScroll,
                key: PageStorageKey(
                  'catalog:${Store.profileScope(widget.client.creds)}:'
                  '$_section:$catId:$_sort:$q',
                ),
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 120),
                gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: columns,
                  // A channel tile is square artwork plus its label. At three
                  // columns on a phone, .82 left less room than the label's
                  // actual line box and produced a repeating 1.5px overflow.
                  childAspectRatio: live ? 0.76 : 0.66,
                  crossAxisSpacing: 13,
                  mainAxisSpacing: 20,
                ),
                itemCount: items.length + (more ? 1 : 0),
                itemBuilder: (_, i) {
                  if (i == items.length) {
                    return Center(
                      child: SizedBox(
                        width: 28,
                        height: 28,
                        child: CircularProgressIndicator(
                          strokeWidth: 2.5,
                          color: accentInk,
                        ),
                      ),
                    );
                  }
                  return live
                      ? ChannelCard(
                          focusNode: _gridFocus[i],
                          onFocusChange: (focused) {
                            if (focused) _lastGridIndex = i;
                          },
                          onKeyEvent: (_, event) => _moveGridFocus(
                            i,
                            event,
                            itemCount: items.length,
                            columns: columns,
                            rowExtent: rowExtent,
                          ),
                          name: items[i].name,
                          logo: items[i].image,
                          index: i,
                          onTap: items[i].onTap,
                        )
                      : PosterCard(
                          focusNode: _gridFocus[i],
                          onFocusChange: (focused) {
                            if (focused) _lastGridIndex = i;
                          },
                          onKeyEvent: (_, event) => _moveGridFocus(
                            i,
                            event,
                            itemCount: items.length,
                            columns: columns,
                            rowExtent: rowExtent,
                          ),
                          name: items[i].name,
                          image: items[i].image,
                          rating: items[i].rating,
                          subtitle: items[i].subtitle,
                          index: i,
                          onTap: items[i].onTap,
                        );
                },
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _group(String id, String title, List<_Res> items) {
    final focusNodes = _searchResultFocus[id]!;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(18, 18, 16, 12),
          child: Text(
            '$title  ·  ${items.length}',
            style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800),
          ),
        ),
        SizedBox(
          height: posterShelfHeight(live: items.first.live),
          child: ListView.separated(
            controller: _searchShelfScroll[id],
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            itemCount: items.length,
            separatorBuilder: (_, __) => const SizedBox(width: 14),
            itemBuilder: (_, i) => SizedBox(
              width: kPosterW,
              child: items[i].live
                  ? ChannelCard(
                      focusNode: focusNodes[i],
                      onKeyEvent: (_, event) =>
                          _moveSearchResultFocus(id, i, event),
                      name: items[i].name,
                      logo: items[i].image,
                      index: i,
                      onTap: items[i].onTap,
                    )
                  : PosterCard(
                      focusNode: focusNodes[i],
                      onKeyEvent: (_, event) =>
                          _moveSearchResultFocus(id, i, event),
                      name: items[i].name,
                      image: items[i].image,
                      rating: items[i].rating,
                      subtitle: items[i].subtitle,
                      index: i,
                      onTap: items[i].onTap,
                    ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _prompt() => Center(
    child: Text(
      'Type a movie, series, or channel name',
      textAlign: TextAlign.center,
      style: TextStyle(color: subtle, fontSize: 14),
    ),
  );

  Widget _empty(String msg) => Center(
    child: Text(msg, style: TextStyle(color: subtle)),
  );
}
