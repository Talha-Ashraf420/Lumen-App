import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../catalog_cache.dart';
import '../device_profile.dart';
import '../downloads.dart';
import '../models.dart';
import '../playback.dart';
import '../refresh.dart';
import '../split.dart';
import '../updater.dart';
import '../responsive.dart';
import '../theme.dart';
import '../widgets.dart';
import '../xtream.dart';
import 'downloads_screen.dart';
import 'home_screen.dart';
import 'update_dialog.dart';
import 'mylist_screen.dart';
import 'profile_screen.dart';
import 'search_screen.dart';

enum HomeBackAction { navigateBack, confirmExit }

HomeBackAction homeBackActionFor(int page) =>
    page == 0 ? HomeBackAction.confirmExit : HomeBackAction.navigateBack;

const catalogResumeRefreshGrace = Duration(seconds: 2);

/// Ignore lifecycle flicker from system overlays, but refresh after Lumen has
/// genuinely been left and reopened. A cold process launch already performs a
/// cached-first provider revalidation through [CatalogCache].
bool shouldRefreshCatalogAfterResume(
  DateTime? backgroundedAt,
  DateTime resumedAt,
) =>
    backgroundedAt != null &&
    resumedAt.difference(backgroundedAt) >= catalogResumeRefreshGrace;

Future<bool> showHomeExitConfirmation(BuildContext context) async =>
    await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Exit Lumen?'),
        content: const Text('Do you want to close the app?'),
        actions: [
          TextButton(
            autofocus: true,
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('No'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Yes'),
          ),
        ],
      ),
    ) ??
    false;

class HomeShell extends StatefulWidget {
  final XtreamClient client;
  final Future<void> Function() onLogout;
  final void Function(XtreamCredentials) onSwitch;
  final Future<List<Category>> Function()? homeCategoryLoader;
  const HomeShell({
    super.key,
    required this.client,
    required this.onLogout,
    required this.onSwitch,
    this.homeCategoryLoader,
  });
  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> with WidgetsBindingObserver {
  int _index = 0;
  late _CatalogCapabilities _capabilities;
  int _capabilityLoad = 0;
  final GlobalKey<SearchScreenState> _searchKey =
      GlobalKey<SearchScreenState>();
  final Map<int, GlobalKey<SearchScreenState>> _catalogKeys = {
    4: GlobalKey<SearchScreenState>(),
    5: GlobalKey<SearchScreenState>(),
    6: GlobalKey<SearchScreenState>(),
  };
  // Auto-refresh the catalog when the app returns to the foreground (throttled),
  // so recently-added movies surface without a manual Refresh.
  DateTime _lastRefresh = DateTime.now();
  DateTime? _backgroundedAt;
  // Tabs initialise only once first opened to avoid a startup request burst.
  final Set<int> _visited = {0};
  final List<int> _navigationHistory = <int>[];
  final Map<int, FocusNode> _dockFocusNodes = <int, FocusNode>{
    0: FocusNode(debugLabel: 'Home dock'),
    1: FocusNode(debugLabel: 'Search dock'),
    2: FocusNode(debugLabel: 'My List dock'),
    3: FocusNode(debugLabel: 'Profile dock'),
    4: FocusNode(debugLabel: 'Movies dock'),
    5: FocusNode(debugLabel: 'Series dock'),
    6: FocusNode(debugLabel: 'Live dock'),
    7: FocusNode(debugLabel: 'Downloads dock'),
  };
  final Map<int, FocusScopeNode> _pageFocusScopes = <int, FocusScopeNode>{
    for (var page = 0; page < 8; page++)
      page: FocusScopeNode(debugLabel: 'Shell page $page'),
  };
  final FocusNode _commandSearchFocus = FocusNode(
    debugLabel: 'Command find anything',
  );
  final FocusNode _commandRefreshFocus = FocusNode(
    debugLabel: 'Command refresh',
  );
  final FocusNode _commandProfileFocus = FocusNode(
    debugLabel: 'Command profile',
  );
  final FocusNode _myListEntryFocus = FocusNode(debugLabel: 'My List filter 0');
  final FocusNode _profileEntryFocus = FocusNode(
    debugLabel: 'Profile add account',
  );
  final FocusNode _homeEntryFocus = FocusNode(debugLabel: 'Home watch now');
  final FocusNode _downloadsEntryFocus = FocusNode(
    debugLabel: 'Downloads filter 0',
  );
  final Map<int, Widget> _pageCache = <int, Widget>{};
  bool _exitDialogOpen = false;

  // Phones and larger screens share the same page map. The phone dock promotes
  // the three catalog pages to first-class destinations, while the account and
  // personal-library pages live in a compact utility hub.
  static const _pageCount = 8;

  bool _allows(int page) => _capabilities.allows(page);

  @override
  void initState() {
    super.initState();
    // Keep the primary library map stable during the first cached/network
    // lookup. Xtream accounts conventionally expose all three catalogs; each
    // request below removes a destination if the provider proves otherwise.
    // M3U profiles are known to be live-only from the outset.
    _capabilities = widget.client.creds.isM3u
        ? const _CatalogCapabilities(live: true)
        : const _CatalogCapabilities(movies: true, series: true, live: true);
    _loadCapabilities();
    contentRefresh.addListener(_loadCapabilities);
    CatalogCache.instance.revision.addListener(_loadCapabilities);
    WidgetsBinding.instance.addObserver(this);
    // Quietly check for a newer build once per launch (skip dev builds).
    if (Updater.instance.isEnabled && kBuildNumber > 0) {
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        final result = await Updater.instance.check();
        if (result.status == UpdateCheckStatus.available && mounted) {
          showUpdateFlow(context, result.info!);
        }
      });
    }
  }

  Future<void> _loadCapabilities() async {
    final generation = ++_capabilityLoad;
    final cache = CatalogCache.instance;
    try {
      if (widget.client.creds.isM3u) {
        final live = await cache.live(widget.client, priority: true);
        if (!mounted || generation != _capabilityLoad) return;
        _setCapabilities(_CatalogCapabilities(live: live.isNotEmpty));
        return;
      }
      // Start the three light category requests together. CatalogCache keeps
      // concurrency bounded, while each completion independently settles its
      // destination instead of waiting for the slowest provider endpoint.
      Future<void> reveal(String kind, Future<List<Category>> request) async {
        final values = await request;
        if (!mounted || generation != _capabilityLoad) return;
        _setCapabilities(
          _CatalogCapabilities(
            movies: kind == 'movie' ? values.isNotEmpty : _capabilities.movies,
            series: kind == 'series' ? values.isNotEmpty : _capabilities.series,
            live: kind == 'live' ? values.isNotEmpty : _capabilities.live,
          ),
        );
      }

      await Future.wait([
        reveal('movie', cache.vod(widget.client, priority: true)),
        reveal('series', cache.series(widget.client, priority: true)),
        reveal('live', cache.live(widget.client, priority: true)),
      ]);
    } catch (_) {
      // A provider may be temporarily unavailable. Keep the conservative
      // destinations already shown; content refresh can retry the catalogs.
    }
  }

  void _setCapabilities(_CatalogCapabilities value) {
    setState(() {
      _capabilities = value;
      if (!_allows(_index)) {
        _index = 0;
        _visited.add(0);
      }
    });
  }

  @override
  void dispose() {
    contentRefresh.removeListener(_loadCapabilities);
    CatalogCache.instance.revision.removeListener(_loadCapabilities);
    WidgetsBinding.instance.removeObserver(this);
    for (final node in _dockFocusNodes.values) {
      node.dispose();
    }
    for (final node in _pageFocusScopes.values) {
      node.dispose();
    }
    _commandSearchFocus.dispose();
    _commandRefreshFocus.dispose();
    _commandProfileFocus.dispose();
    _myListEntryFocus.dispose();
    _profileEntryFocus.dispose();
    _homeEntryFocus.dispose();
    _downloadsEntryFocus.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // App is being torn down: dispose the mpv players BEFORE the Flutter engine
    // shuts down, otherwise the still-running video render thread frees its
    // platform-view/texture out from under the compositor → SIGABRT on quit.
    if (state == AppLifecycleState.detached) {
      try {
        SplitController.instance.close();
      } catch (_) {}
      try {
        PlaybackController.instance.stop();
      } catch (_) {}
      return;
    }
    if (state == AppLifecycleState.hidden ||
        state == AppLifecycleState.paused) {
      _backgroundedAt ??= DateTime.now();
      return;
    }
    if (state != AppLifecycleState.resumed) return;
    final now = DateTime.now();
    final backgroundedAt = _backgroundedAt;
    _backgroundedAt = null;
    // Provider catalogs can be very large, so ignore only momentary
    // lifecycle flicker. Every genuine foreground return revalidates in the
    // background while SearchScreen keeps its last good rows mounted.
    if (shouldRefreshCatalogAfterResume(backgroundedAt, now) ||
        now.difference(_lastRefresh) > const Duration(minutes: 30)) {
      _lastRefresh = now;
      refreshContent();
    }
  }

  Widget _pageFor(int i) => switch (i) {
    0 => HomeScreen(
      client: widget.client,
      onBrowse: () => _select(1),
      entryFocusNode: _homeEntryFocus,
      categoryLoader: widget.homeCategoryLoader,
    ),
    1 => SearchScreen(
      key: _searchKey,
      client: widget.client,
      shellRailFocusNode: _dockFocusNodes[1],
      shellTopFocusNode: _commandRefreshFocus,
    ),
    2 => MyListScreen(
      client: widget.client,
      shellRailFocusNode: _dockFocusNodes[2],
      shellTopFocusNode: _commandSearchFocus,
      entryFocusNode: _myListEntryFocus,
    ),
    3 => ProfileScreen(
      client: widget.client,
      onLogout: widget.onLogout,
      onSwitch: widget.onSwitch,
      shellRailFocusNode: _dockFocusNodes[3],
      shellTopFocusNode: _commandSearchFocus,
      entryFocusNode: _profileEntryFocus,
    ),
    4 => SearchScreen(
      key: _catalogKeys[4],
      client: widget.client,
      initialSection: 'movie',
      shellRailFocusNode: _dockFocusNodes[4],
      shellTopFocusNode: _commandSearchFocus,
    ),
    5 => SearchScreen(
      key: _catalogKeys[5],
      client: widget.client,
      initialSection: 'series',
      shellRailFocusNode: _dockFocusNodes[5],
      shellTopFocusNode: _commandSearchFocus,
    ),
    6 => SearchScreen(
      key: _catalogKeys[6],
      client: widget.client,
      initialSection: 'live',
      shellRailFocusNode: _dockFocusNodes[6],
      shellTopFocusNode: _commandSearchFocus,
    ),
    _ => DownloadsScreen(
      client: widget.client,
      shellRailFocusNode: _dockFocusNodes[7],
      shellTopFocusNode: _commandSearchFocus,
      entryFocusNode: _downloadsEntryFocus,
    ),
  };

  Widget _cachedPage(int page) =>
      _pageCache.putIfAbsent(page, () => _pageFor(page));

  KeyEventResult _handlePageBoundaryKey(int page, KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    final key = event.logicalKey;
    if (key != LogicalKeyboardKey.arrowLeft &&
        key != LogicalKeyboardKey.arrowUp) {
      return KeyEventResult.ignored;
    }
    final rail = _dockFocusNodes[page];
    final scope = _pageFocusScopes[page];
    final pageContext = _pageFocusScopes[page]?.context;
    final focusedContext = FocusManager.instance.primaryFocus?.context;
    if (pageContext == null ||
        !pageContext.mounted ||
        focusedContext == null ||
        !focusedContext.mounted) {
      return KeyEventResult.ignored;
    }
    final pageBox = pageContext.findRenderObject();
    final focusedBox = focusedContext.findRenderObject();
    if (rail == null ||
        scope == null ||
        !rail.canRequestFocus ||
        pageBox is! RenderBox ||
        focusedBox is! RenderBox) {
      return KeyEventResult.ignored;
    }
    final focusedCenter = focusedBox.localToGlobal(
      focusedBox.size.center(Offset.zero),
    );
    if (key == LogicalKeyboardKey.arrowLeft) {
      final pageLeft = pageBox.localToGlobal(Offset.zero).dx;
      final focusedRect =
          focusedBox.localToGlobal(Offset.zero) & focusedBox.size;
      // Focus key handlers run before geometry traversal. A control can sit in
      // the leftmost part of the page while still having a genuine same-row
      // neighbour (the first Home spotlight cards are the important case).
      // Let traversal reach that neighbour before treating the page as having
      // reached its navigation-rail boundary.
      final hasFocusableLeftInLane = scope.traversalDescendants.any((node) {
        if (node == FocusManager.instance.primaryFocus ||
            _isStructuralFocusNode(node) ||
            !node.canRequestFocus ||
            node.skipTraversal) {
          return false;
        }
        final nodeContext = node.context;
        if (nodeContext == null || !nodeContext.mounted) return false;
        final box = nodeContext.findRenderObject();
        if (box is! RenderBox) return false;
        final rect = box.localToGlobal(Offset.zero) & box.size;
        if (rect.center.dx >= focusedRect.center.dx - 8) return false;
        final overlapTop = rect.top > focusedRect.top
            ? rect.top
            : focusedRect.top;
        final overlapBottom = rect.bottom < focusedRect.bottom
            ? rect.bottom
            : focusedRect.bottom;
        final smallerHeight = rect.height < focusedRect.height
            ? rect.height
            : focusedRect.height;
        return overlapBottom - overlapTop >= smallerHeight * .35;
      });
      if (hasFocusableLeftInLane) return KeyEventResult.ignored;

      // With no same-row neighbour, a control in the page's left zone has
      // genuinely reached the stable shell rail boundary.
      if (focusedCenter.dx <= pageLeft + pageBox.size.width * .28) {
        rail.requestFocus();
        return KeyEventResult.handled;
      }
      return KeyEventResult.ignored;
    }

    // Focus key handlers run before Flutter's geometry traversal. Only claim
    // Up when this is genuinely the topmost actionable control in the page;
    // otherwise grids, rows and settings lists keep their normal Up movement.
    final hasFocusableAbove = scope.traversalDescendants.any((node) {
      if (node == FocusManager.instance.primaryFocus ||
          _isStructuralFocusNode(node) ||
          !node.canRequestFocus ||
          node.skipTraversal) {
        return false;
      }
      final nodeContext = node.context;
      if (nodeContext == null || !nodeContext.mounted) return false;
      final box = nodeContext.findRenderObject();
      if (box is! RenderBox) return false;
      final center = box.localToGlobal(box.size.center(Offset.zero));
      return center.dy < focusedCenter.dy - 8;
    });
    if (hasFocusableAbove) return KeyEventResult.ignored;
    final commandEntry = page == 1 ? _commandRefreshFocus : _commandSearchFocus;
    if (commandEntry.canRequestFocus) {
      commandEntry.requestFocus();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  bool _isStructuralFocusNode(FocusNode node) =>
      node is FocusScopeNode ||
      node.debugLabel == 'Shortcuts' ||
      node.debugLabel == 'FocusTraversalGroup';

  void _focusPageContent(int page, {bool defer = true}) {
    void request() {
      if (!mounted || page != _index) return;
      if (page == 1) {
        _searchKey.currentState?.focusSearch();
        return;
      }
      if (page >= 4 && page <= 6) {
        _catalogKeys[page]?.currentState?.focusCatalogEntry();
        return;
      }
      final scope = _pageFocusScopes[page];
      if (scope == null) return;
      bool isMountedTarget(FocusNode node) {
        final nodeContext = node.context;
        return nodeContext != null &&
            nodeContext.mounted &&
            node.canRequestFocus;
      }

      if (page == 0 && isMountedTarget(_homeEntryFocus)) {
        scope.requestFocus(_homeEntryFocus);
        return;
      }
      // My List can change from an empty, non-focusable page to a populated
      // one while its cached page stays mounted. Use its stable first filter
      // node instead of relying on a traversal snapshot from the empty state.
      if (page == 2 && isMountedTarget(_myListEntryFocus)) {
        scope.requestFocus(_myListEntryFocus);
        return;
      }
      if (page == 3 && isMountedTarget(_profileEntryFocus)) {
        scope.requestFocus(_profileEntryFocus);
        return;
      }
      if (page == 7 && isMountedTarget(_downloadsEntryFocus)) {
        scope.requestFocus(_downloadsEntryFocus);
        return;
      }
      final candidates = <FocusNode>[];
      for (final node in scope.traversalDescendants) {
        // CallbackShortcuts/Shortcuts insert focusable implementation nodes.
        // They are not controls, and choosing one traps all four D-pad keys on
        // the page wrapper. Enter the first real descendant instead.
        if (!_isStructuralFocusNode(node) &&
            isMountedTarget(node) &&
            !node.skipTraversal) {
          candidates.add(node);
        }
      }
      final named = candidates.where(
        (node) => node.debugLabel?.trim().isNotEmpty ?? false,
      );
      final target = named.isNotEmpty
          ? named.first
          : page == 0 && candidates.isNotEmpty
          ? candidates.first
          : null;
      if (target != null) {
        // Re-enter through the page scope. Directly requesting a descendant
        // after focus has moved to the sibling command bar can leave the root
        // scope primary for one frame on Android TV.
        scope.requestFocus(target);
        return;
      }
      // Loading and empty pages may not yet expose a content action. Enter the
      // command bar instead of leaving Right trapped on the shell rail.
      final commandEntry = page == 1
          ? _commandRefreshFocus
          : _commandSearchFocus;
      if (commandEntry.canRequestFocus) commandEntry.requestFocus();
    }

    if (defer) {
      WidgetsBinding.instance.addPostFrameCallback((_) => request());
      // Hardware key dispatch does not guarantee a subsequent frame. Make
      // sure the rail-to-page handoff actually runs on Android TV instead of
      // waiting for unrelated animation or pointer activity.
      WidgetsBinding.instance.ensureVisualUpdate();
    } else {
      request();
    }
  }

  void _select(int i, {bool rememberCurrent = true, bool focusContent = true}) {
    if (!_allows(i)) return;
    if (i == _index) {
      if (focusContent) _focusPageContent(i);
      return;
    }
    if (i != _index) HapticFeedback.selectionClick();
    if (rememberCurrent) {
      if (i == 0) {
        _navigationHistory.clear();
      } else {
        _navigationHistory.remove(_index);
        _navigationHistory.add(_index);
      }
    }
    setState(() => _index = i);
    if (!focusContent) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _dockFocusNodes[i]?.requestFocus();
      });
    }
    if (focusContent && i != 0) {
      _focusPageContent(i);
    } else if (i == 0) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _dockFocusNodes[0]!.requestFocus();
      });
    }
  }

  void _selectDockAfterFocusSettles(int page) {
    // Focus callbacks run outside build, so cached destinations can switch
    // immediately without the old debounce or an additional frame of latency.
    if (!mounted || !(_dockFocusNodes[page]?.hasFocus ?? false)) return;
    _select(page, focusContent: false);
  }

  Future<void> _handleBack(bool didPop) async {
    if (didPop) return;
    final playback = PlaybackController.instance;
    if (playback.hasMedia && !playback.minimized) return;
    if (homeBackActionFor(_index) == HomeBackAction.navigateBack) {
      final target = _navigationHistory.isEmpty
          ? 0
          : _navigationHistory.removeLast();
      _select(target, rememberCurrent: false);
      return;
    }
    if (_exitDialogOpen) return;
    _exitDialogOpen = true;
    final shouldExit = await showHomeExitConfirmation(context);
    _exitDialogOpen = false;
    if (shouldExit && mounted) await SystemNavigator.pop();
  }

  @override
  Widget build(BuildContext context) {
    _visited.add(_index);
    final pages = [
      for (var i = 0; i < _pageCount; i++)
        ExcludeFocus(
          key: ValueKey('shell-page-$i'),
          excluding: i != _index,
          child: FocusScope(
            node: _pageFocusScopes[i],
            onKeyEvent: (_, event) => _handlePageBoundaryKey(i, event),
            child: TickerMode(
              // Keep each visited page as the same widget instance. Besides
              // preserving state, this prevents all heavy offstage utility and
              // catalog pages from rebuilding on every rail focus change.
              enabled: i == _index,
              child: _visited.contains(i)
                  ? _cachedPage(i)
                  : const SizedBox.shrink(),
            ),
          ),
        ),
    ];
    final wide = isWide(context);
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) => _handleBack(didPop),
      child: CallbackShortcuts(
        bindings: {
          const SingleActivator(LogicalKeyboardKey.keyK, meta: true): () =>
              _select(1),
          const SingleActivator(LogicalKeyboardKey.keyK, control: true): () =>
              _select(1),
        },
        child: Focus(
          child: Scaffold(
            resizeToAvoidBottomInset: !DeviceProfile.isTelevision,
            body: Stack(
              children: [
                Aurora(),
                if (wide) _wideLayout(pages) else _mobileLayout(pages),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // Desktop: a fixed signal dock and a calm content stage. Navigation never
  // expands over the artwork, so the spatial map stays stable for mouse + TV.
  Widget _wideLayout(List<Widget> pages) {
    return SafeArea(
      child: Row(
        children: [
          _SignalDock(
            index: _index,
            capabilities: _capabilities,
            onSelect: (page) => _select(page),
            onFocusSelect: _selectDockAfterFocusSettles,
            focusNodes: _dockFocusNodes,
          ),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(0, 10, 10, 10),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(28),
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [
                        surface.withValues(alpha: isDark ? 0.92 : 0.96),
                        bg.withValues(alpha: isDark ? 0.96 : 0.94),
                      ],
                    ),
                    border: Border.all(color: lineStrong),
                  ),
                  child: Column(
                    children: [
                      _CommandBar(
                        index: _index,
                        onSearch: () => _select(1),
                        onProfile: () => _select(3),
                        onFocusContent: () =>
                            _focusPageContent(_index, defer: false),
                        railFocusNode: _dockFocusNodes[_index]!,
                        searchFocusNode: _commandSearchFocus,
                        refreshFocusNode: _commandRefreshFocus,
                        profileFocusNode: _commandProfileFocus,
                      ),
                      Expanded(
                        child: IndexedStack(index: _index, children: pages),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ---- mobile: floating bottom nav ----
  Widget _mobileLayout(List<Widget> pages) {
    return Stack(
      children: [
        SafeArea(
          bottom: false,
          child: IndexedStack(index: _index, children: pages),
        ),
        if (_index == 0)
          Positioned(
            top: 4,
            right: 16,
            child: SafeArea(bottom: false, child: _mobileUtilityButton()),
          ),
        Align(
          alignment: Alignment.bottomCenter,
          child: SafeArea(
            top: false,
            // Draw the page edge-to-edge, but keep every navigation target
            // above Android's gesture handle or three-button navigation bar.
            minimum: const EdgeInsets.fromLTRB(16, 0, 16, 22),
            child:
                Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 7,
                        vertical: 7,
                      ),
                      decoration: BoxDecoration(
                        color: surface.withValues(alpha: 0.96),
                        borderRadius: BorderRadius.circular(24),
                        border: Border.all(color: line),
                        boxShadow: glow(Colors.black, blur: 26, y: 12),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [for (final nav in _mobileDock) _item(nav)],
                      ),
                    )
                    .animate()
                    .fadeIn(delay: 150.ms)
                    .slideY(begin: 0.6, end: 0, curve: Curves.easeOutBack),
          ),
        ),
      ],
    );
  }

  List<_Nav> get _mobileDock => <_Nav>[
    const _Nav(Icons.home_rounded, 'Home', 0),
    if (_capabilities.movies)
      const _Nav(Icons.movie_filter_rounded, 'Movies', 4),
    if (_capabilities.series)
      const _Nav(Icons.amp_stories_rounded, 'Series', 5),
    if (_capabilities.live) const _Nav(Icons.sensors_rounded, 'Live', 6),
    const _Nav(Icons.search_rounded, 'Search', 1),
  ];

  Widget _mobileUtilityButton() {
    final username = widget.client.creds.username.trim();
    final initial = username.isEmpty ? 'L' : username[0].toUpperCase();
    return Tooltip(
      message: 'You & library',
      child: RemoteTap(
        behavior: HitTestBehavior.opaque,
        onTap: _openMobileUtilityHub,
        child: Container(
          width: 50,
          height: 50,
          decoration: BoxDecoration(
            color: surface.withValues(alpha: 0.96),
            borderRadius: BorderRadius.circular(17),
            border: Border.all(color: line),
            boxShadow: glow(Colors.black, blur: 16, y: 6),
          ),
          child: Stack(
            alignment: Alignment.center,
            children: [
              Text(
                initial,
                style: TextStyle(
                  color: textHi,
                  fontWeight: FontWeight.w800,
                  fontSize: 16,
                ),
              ),
              Positioned(
                right: 7,
                bottom: 7,
                child: Container(
                  width: 6,
                  height: 6,
                  decoration: BoxDecoration(
                    color: accentInk,
                    shape: BoxShape.circle,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _openMobileUtilityHub() async {
    final destination = await showModalBottomSheet<int>(
      context: context,
      useSafeArea: true,
      isScrollControlled: false,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black.withValues(alpha: 0.58),
      builder: (_) => _MobileUtilityHub(client: widget.client),
    );
    if (!mounted || destination == null) return;
    _select(destination);
  }

  Widget _item(_Nav nav) {
    final sel = nav.page == _index;
    return RemoteTap(
      focusNode: _dockFocusNodes[nav.page],
      onFocusChange: (focused) {
        if (focused && !sel) _select(nav.page);
      },
      behavior: HitTestBehavior.opaque,
      onTap: () => _select(nav.page),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 280),
        curve: Curves.easeOut,
        margin: const EdgeInsets.symmetric(horizontal: 2),
        padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 8),
        decoration: BoxDecoration(
          color: sel ? accentInk.withValues(alpha: isDark ? 0.12 : 0.09) : null,
          borderRadius: BorderRadius.circular(17),
          border: sel
              ? Border.all(
                  color: accentInk.withValues(alpha: isDark ? 0.28 : 0.42),
                )
              : null,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(nav.icon, size: 20, color: sel ? accentInk : muted),
            const SizedBox(height: 3),
            Text(
              nav.label,
              style: TextStyle(
                fontWeight: sel ? FontWeight.w700 : FontWeight.w500,
                color: sel ? textHi : subtle,
                fontSize: 9.5,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MobileUtilityHub extends StatelessWidget {
  const _MobileUtilityHub({required this.client});

  final XtreamClient client;

  @override
  Widget build(BuildContext context) {
    final username = client.creds.username.trim();
    final host = Uri.tryParse(client.creds.baseUrl)?.host;
    final account = username.isEmpty ? (host ?? 'Local library') : username;
    return Material(
      color: Colors.transparent,
      child: Container(
        margin: const EdgeInsets.fromLTRB(12, 0, 12, 12),
        padding: const EdgeInsets.fromLTRB(18, 10, 18, 18),
        decoration: BoxDecoration(
          color: surface,
          borderRadius: BorderRadius.circular(28),
          border: Border.all(color: line),
          boxShadow: glow(Colors.black, blur: 32, y: 12),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 38,
                height: 4,
                decoration: BoxDecoration(
                  color: line,
                  borderRadius: BorderRadius.circular(3),
                ),
              ),
            ),
            const SizedBox(height: 18),
            Row(
              children: [
                Container(
                  width: 42,
                  height: 42,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: accent,
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Text(
                    account.isEmpty ? 'L' : account[0].toUpperCase(),
                    style: TextStyle(
                      color: onAccent,
                      fontSize: 17,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Your Lumen',
                        style: kTitle().copyWith(fontSize: 20),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        account,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(color: muted, fontSize: 12),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  tooltip: 'Close',
                  onPressed: () => Navigator.pop(context),
                  icon: Icon(Icons.close_rounded, color: muted),
                ),
              ],
            ),
            const SizedBox(height: 18),
            Text(
              'SAVED & PERSONAL',
              style: TextStyle(
                color: subtle,
                fontSize: 10,
                letterSpacing: 1.7,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: _MobileUtilityDestination(
                    icon: Icons.favorite_rounded,
                    label: 'My List',
                    subtitle: 'Saved titles',
                    autofocus: true,
                    onTap: () => Navigator.pop(context, 2),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _MobileUtilityDestination(
                    icon: Icons.download_rounded,
                    label: 'Downloads',
                    subtitle: 'Watch offline',
                    onTap: () => Navigator.pop(context, 7),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            _MobileUtilityDestination(
              icon: Icons.person_outline_rounded,
              label: 'Profile & settings',
              subtitle: 'Account, appearance, privacy and app controls',
              onTap: () => Navigator.pop(context, 3),
              horizontal: true,
            ),
          ],
        ),
      ),
    );
  }
}

class _MobileUtilityDestination extends StatelessWidget {
  const _MobileUtilityDestination({
    required this.icon,
    required this.label,
    required this.subtitle,
    required this.onTap,
    this.horizontal = false,
    this.autofocus = false,
  });

  final IconData icon;
  final String label;
  final String subtitle;
  final VoidCallback onTap;
  final bool horizontal;
  final bool autofocus;

  @override
  Widget build(BuildContext context) {
    return RemoteTap(
      autofocus: autofocus,
      onTap: onTap,
      child: Container(
        height: horizontal ? 68 : 92,
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: surfaceHi,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: line),
        ),
        child: horizontal
            ? Row(
                children: [
                  _icon(),
                  const SizedBox(width: 12),
                  Expanded(child: _copy()),
                  Icon(Icons.chevron_right_rounded, color: muted),
                ],
              )
            : Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [_icon(), const Spacer(), _copy()],
              ),
      ),
    );
  }

  Widget _icon() => Icon(icon, color: accentInk, size: 21);

  Widget _copy() => Column(
    mainAxisSize: MainAxisSize.min,
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        label,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          color: textHi,
          fontSize: 13,
          fontWeight: FontWeight.w700,
        ),
      ),
      const SizedBox(height: 2),
      Text(
        subtitle,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(color: subtle, fontSize: 10.5),
      ),
    ],
  );
}

// ── Signal dock ──────────────────────────────────────────────────────────────
class _CatalogCapabilities {
  final bool movies;
  final bool series;
  final bool live;
  const _CatalogCapabilities({
    this.movies = false,
    this.series = false,
    this.live = false,
  });

  bool allows(int page) => switch (page) {
    4 => movies,
    5 => series,
    6 => live,
    _ => true,
  };
}

class _Nav {
  final IconData icon;
  final String label;
  final int page;
  final bool trailingIsDownloads;
  const _Nav(
    this.icon,
    this.label,
    this.page, {
    this.trailingIsDownloads = false,
  });
}

const List<_Nav> _mainDock = [
  _Nav(Icons.home_rounded, 'Home', 0),
  _Nav(Icons.movie_filter_rounded, 'Movies', 4),
  _Nav(Icons.amp_stories_rounded, 'Series', 5),
  _Nav(Icons.sensors_rounded, 'Live', 6),
  _Nav(Icons.search_rounded, 'Search', 1),
];

const List<_Nav> _utilityDock = [
  _Nav(Icons.favorite_rounded, 'My List', 2),
  _Nav(Icons.download_rounded, 'Downloads', 7, trailingIsDownloads: true),
  _Nav(Icons.person_rounded, 'Profile', 3),
];

class _SignalDock extends StatelessWidget {
  final int index;
  final _CatalogCapabilities capabilities;
  final ValueChanged<int> onSelect;
  final ValueChanged<int> onFocusSelect;
  final Map<int, FocusNode> focusNodes;
  const _SignalDock({
    required this.index,
    required this.capabilities,
    required this.onSelect,
    required this.onFocusSelect,
    required this.focusNodes,
  });

  @override
  Widget build(BuildContext context) {
    final main = _mainDock
        .where((nav) => capabilities.allows(nav.page))
        .toList();
    final ordered = <_Nav>[...main, ..._utilityDock];

    KeyEventResult moveInRail(int page, KeyEvent event) {
      if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
        return KeyEventResult.ignored;
      }
      final current = ordered.indexWhere((nav) => nav.page == page);
      if (current < 0) return KeyEventResult.ignored;
      if (event.logicalKey == LogicalKeyboardKey.arrowRight) {
        onSelect(page);
        return KeyEventResult.handled;
      }
      if (event.logicalKey == LogicalKeyboardKey.arrowLeft) {
        // The rail is the left edge of the app. Keep its focus visible.
        return KeyEventResult.handled;
      }
      final delta = event.logicalKey == LogicalKeyboardKey.arrowUp
          ? -1
          : event.logicalKey == LogicalKeyboardKey.arrowDown
          ? 1
          : 0;
      if (delta == 0) return KeyEventResult.ignored;
      final target = (current + delta).clamp(0, ordered.length - 1);
      focusNodes[ordered[target].page]?.requestFocus();
      return KeyEventResult.handled;
    }

    return SizedBox(
      width: 86,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
        child: Column(
          children: [
            const SizedBox(height: 6),
            Tooltip(
              message: 'Lumen',
              child: Container(
                width: 46,
                height: 46,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      accentInk.withValues(alpha: isDark ? .16 : .10),
                      accentInk.withValues(alpha: .025),
                    ],
                  ),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: lineStrong),
                ),
                child: const LumenMark(size: 25),
              ),
            ),
            const SizedBox(height: 26),
            for (final nav in main)
              _DockItem(
                nav: nav,
                selected: nav.page == index,
                onTap: () => onSelect(nav.page),
                onFocusSelect: () => onFocusSelect(nav.page),
                focusNode: focusNodes[nav.page],
                onKeyEvent: (_, event) => moveInRail(nav.page, event),
              ),
            const Spacer(),
            Container(
              height: 1,
              margin: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
              color: line,
            ),
            for (final nav in _utilityDock)
              _DockItem(
                nav: nav,
                selected: nav.page == index,
                onTap: () => onSelect(nav.page),
                onFocusSelect: () => onFocusSelect(nav.page),
                focusNode: focusNodes[nav.page],
                onKeyEvent: (_, event) => moveInRail(nav.page, event),
              ),
          ],
        ),
      ),
    );
  }
}

class _DockItem extends StatelessWidget {
  final _Nav nav;
  final bool selected;
  final VoidCallback onTap;
  final VoidCallback onFocusSelect;
  final FocusNode? focusNode;
  final FocusOnKeyEventCallback? onKeyEvent;
  const _DockItem({
    required this.nav,
    required this.selected,
    required this.onTap,
    required this.onFocusSelect,
    this.focusNode,
    this.onKeyEvent,
  });

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: nav.label,
      waitDuration: const Duration(milliseconds: 450),
      child: FocusableTap(
        autofocus: nav.page == 0,
        focusNode: focusNode,
        onKeyEvent: onKeyEvent,
        // Primary TV destinations behave like tabs: landing on one with the
        // D-pad reveals that page immediately. Media/action controls still
        // require Select, so browsing can never start playback accidentally.
        onFocusChange: (focused) {
          if (focused && !selected) onFocusSelect();
        },
        onTap: onTap,
        builder: (context, active) => AnimatedContainer(
          duration: lumenMotion,
          width: 54,
          height: 46,
          // Nine dock entries must fit a 540dp TV viewport after SafeArea.
          margin: const EdgeInsets.only(bottom: 2),
          decoration: BoxDecoration(
            gradient: selected
                ? LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      accentInk.withValues(alpha: isDark ? .20 : .13),
                      accentInk.withValues(alpha: isDark ? .08 : .045),
                    ],
                  )
                : null,
            color: selected
                ? null
                : (active ? surfaceRaised : Colors.transparent),
            borderRadius: BorderRadius.circular(15),
            border: Border.all(
              color: selected
                  ? accentInk.withValues(alpha: isDark ? 0.36 : 0.48)
                  : (active ? lineStrong : Colors.transparent),
            ),
          ),
          child: Stack(
            children: [
              Center(
                child: Icon(
                  nav.icon,
                  size: 21,
                  color: selected ? accentInk : (active ? textHi : muted),
                ),
              ),
              if (selected)
                Positioned(
                  left: 3,
                  top: 13,
                  bottom: 13,
                  child: Container(
                    width: 2,
                    decoration: BoxDecoration(
                      color: accentInk,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
              if (nav.trailingIsDownloads)
                AnimatedBuilder(
                  animation: Downloads.instance,
                  builder: (context, child) {
                    final hasActive = Downloads.instance.items.any(
                      (d) =>
                          d.status == DlStatus.downloading ||
                          d.status == DlStatus.queued,
                    );
                    return hasActive
                        ? Positioned(
                            right: 8,
                            top: 7,
                            child: Container(
                              width: 6,
                              height: 6,
                              decoration: BoxDecoration(
                                color: accentInk,
                                shape: BoxShape.circle,
                              ),
                            ),
                          )
                        : const SizedBox.shrink();
                  },
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CommandBar extends StatelessWidget {
  final int index;
  final VoidCallback onSearch;
  final VoidCallback onProfile;
  final VoidCallback onFocusContent;
  final FocusNode railFocusNode;
  final FocusNode searchFocusNode;
  final FocusNode refreshFocusNode;
  final FocusNode profileFocusNode;
  const _CommandBar({
    required this.index,
    required this.onSearch,
    required this.onProfile,
    required this.onFocusContent,
    required this.railFocusNode,
    required this.searchFocusNode,
    required this.refreshFocusNode,
    required this.profileFocusNode,
  });

  static const _titles = <int, String>{
    0: 'Tonight',
    1: 'Search library',
    2: 'My list',
    3: 'Profile',
    4: 'Movies',
    5: 'Series',
    6: 'Live signal',
    7: 'Downloads',
  };

  KeyEventResult _moveCommandFocus(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    final key = event.logicalKey;
    final nodes = <FocusNode>[
      if (index != 1) searchFocusNode,
      refreshFocusNode,
      profileFocusNode,
    ];
    final current = nodes.indexOf(node);
    if (current < 0) return KeyEventResult.ignored;
    if (key == LogicalKeyboardKey.arrowLeft) {
      if (current > 0) {
        nodes[current - 1].requestFocus();
      } else {
        // Cross sibling scopes after this key dispatch finishes. Requesting
        // the rail synchronously while the command-bar Focus is handling Left
        // can briefly promote rootScope and make focus appear to vanish.
        WidgetsBinding.instance.addPostFrameCallback((_) {
          final railContext = railFocusNode.context;
          if (railContext != null &&
              railContext.mounted &&
              railFocusNode.canRequestFocus) {
            railFocusNode.requestFocus();
          }
        });
        // A hardware key does not necessarily schedule another Flutter frame.
        // Without this, the queued cross-scope handoff can remain pending and
        // make Left appear dead on televisions until an unrelated repaint.
        WidgetsBinding.instance.ensureVisualUpdate();
      }
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowRight) {
      if (current + 1 < nodes.length) nodes[current + 1].requestFocus();
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowUp) {
      // The command bar is the top edge; keep focus visible there.
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowDown) {
      // Geometry traversal can select an implementation FocusScope when a
      // cached page has just changed from empty to populated. Enter through
      // the page's explicit focus handoff so the highlight never disappears.
      if (index == 2 || !node.focusInDirection(TraversalDirection.down)) {
        onFocusContent();
      }
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 72,
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: line)),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24),
        child: Row(
          children: [
            Text(
              _titles[index] ?? 'Lumen',
              style: kTitle().copyWith(fontSize: 25),
            ),
            const SizedBox(width: 12),
            Container(
              width: 5,
              height: 5,
              decoration: BoxDecoration(
                color: accentInk,
                shape: BoxShape.circle,
              ),
            ),
            const Spacer(),
            if (index != 1) ...[
              FocusableTap(
                focusNode: searchFocusNode,
                onKeyEvent: _moveCommandFocus,
                onTap: onSearch,
                builder: (_, active) => AnimatedContainer(
                  duration: lumenMotion,
                  width: 252,
                  height: 42,
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                  decoration: BoxDecoration(
                    color: active ? surfaceRaised : surface,
                    borderRadius: BorderRadius.circular(15),
                    border: Border.all(color: active ? accentInk : lineStrong),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.search_rounded, size: 18, color: muted),
                      const SizedBox(width: 9),
                      Expanded(
                        child: Text(
                          'Find anything',
                          style: TextStyle(color: subtle, fontSize: 13),
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 7,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: surfaceHi,
                          borderRadius: BorderRadius.circular(7),
                          border: Border.all(color: line),
                        ),
                        child: Text(
                          '⌘ K',
                          style: TextStyle(
                            color: muted,
                            fontSize: 10,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 10),
            ],
            FocusableTap(
              focusNode: refreshFocusNode,
              onKeyEvent: _moveCommandFocus,
              focusRadius: 12,
              onTap: () {
                refreshContent();
                ScaffoldMessenger.of(context)
                  ..hideCurrentSnackBar()
                  ..showSnackBar(
                    const SnackBar(
                      content: Text('Refreshing library…'),
                      duration: Duration(seconds: 2),
                    ),
                  );
              },
              builder: (_, active) => Tooltip(
                message: 'Refresh library',
                child: AnimatedContainer(
                  duration: lumenMotion,
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: active ? accent : Colors.transparent,
                    borderRadius: BorderRadius.circular(13),
                    border: Border.all(
                      color: active ? accent : Colors.transparent,
                    ),
                  ),
                  alignment: Alignment.center,
                  child: Icon(
                    Icons.sync_rounded,
                    color: active ? onAccent : muted,
                    size: 20,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 6),
            FocusableTap(
              focusNode: profileFocusNode,
              onKeyEvent: _moveCommandFocus,
              onTap: onProfile,
              builder: (_, active) => AnimatedContainer(
                duration: lumenMotion,
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: active ? accent : surfaceRaised,
                  borderRadius: BorderRadius.circular(13),
                  border: Border.all(color: active ? accent : lineStrong),
                ),
                child: Icon(
                  Icons.person_outline_rounded,
                  size: 19,
                  color: active ? onAccent : textHi,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
