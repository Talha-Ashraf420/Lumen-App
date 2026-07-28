import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../catalog_cache.dart';
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
import 'epg_guide_screen.dart';
import 'home_screen.dart';
import 'update_dialog.dart';
import 'mylist_screen.dart';
import 'profile_screen.dart';
import 'search_screen.dart';

class HomeShell extends StatefulWidget {
  final XtreamClient client;
  final Future<void> Function() onLogout;
  final void Function(XtreamCredentials) onSwitch;
  const HomeShell({
    super.key,
    required this.client,
    required this.onLogout,
    required this.onSwitch,
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
  // Auto-refresh the catalog when the app returns to the foreground (throttled),
  // so recently-added movies surface without a manual Refresh.
  DateTime _lastRefresh = DateTime.now();
  // Tabs initialise only once first opened — avoids a startup request burst
  // (e.g. the Live guide loading EPG) that can trip the provider.
  final Set<int> _visited = {0};

  // Mobile destinations occupy 0–3. Desktop adds Movies, Series, Live,
  // TV Guide, and Downloads at 4–8.
  static const _pageCount = 9;

  bool _allows(int page) => _capabilities.allows(page);

  @override
  void initState() {
    super.initState();
    _capabilities = _CatalogCapabilities(live: widget.client.creds.isM3u);
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
      // concurrency bounded, while each completion progressively unlocks its
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
    if (state != AppLifecycleState.resumed) return;
    final now = DateTime.now();
    // Keep the warm in-memory catalog when briefly switching apps. Providers
    // can expose tens of thousands of entries, so a three-minute expiry made
    // returning to Lumen needlessly repeat all of that work.
    if (now.difference(_lastRefresh) > const Duration(minutes: 30)) {
      _lastRefresh = now;
      refreshContent();
    }
  }

  Widget _pageFor(int i) => switch (i) {
    0 => HomeScreen(client: widget.client, onBrowse: () => _select(1)),
    1 => SearchScreen(key: _searchKey, client: widget.client),
    2 => MyListScreen(client: widget.client),
    3 => ProfileScreen(
      client: widget.client,
      onLogout: widget.onLogout,
      onSwitch: widget.onSwitch,
    ),
    4 => SearchScreen(client: widget.client, initialSection: 'movie'),
    5 => SearchScreen(client: widget.client, initialSection: 'series'),
    6 => SearchScreen(client: widget.client, initialSection: 'live'),
    7 => EpgGuideScreen(client: widget.client),
    _ => DownloadsScreen(client: widget.client),
  };

  void _select(int i) {
    if (!_allows(i)) return;
    if (i != _index) HapticFeedback.selectionClick();
    setState(() => _index = i);
    if (i == 1) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _searchKey.currentState?.focusSearch();
      });
    }
  }

  void _handleMobileBack(bool didPop) {
    if (didPop) return;
    // A back swipe inside the main shell is navigation, not an instruction to
    // tear down the Flutter engine. Returning to Home also avoids the native
    // video surface being disposed mid-gesture on some Android/Google TV
    // devices. A second swipe on Home is intentionally ignored; the Android
    // Home/Recents controls remain the safe way to leave the player.
    if (_index != 0) _select(0);
  }

  @override
  Widget build(BuildContext context) {
    _visited.add(_index);
    final pages = [
      for (var i = 0; i < _pageCount; i++)
        TickerMode(
          // IndexedStack preserves visited pages for instant tab switching.
          // Explicitly pause their animations while offstage so every Aurora,
          // shimmer and transition does not continue consuming frames.
          enabled: i == _index,
          child: _visited.contains(i) ? _pageFor(i) : const SizedBox.shrink(),
        ),
    ];
    final wide = isWide(context);
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) => _handleMobileBack(didPop),
      child: CallbackShortcuts(
        bindings: {
          const SingleActivator(LogicalKeyboardKey.keyK, meta: true): () =>
              _select(1),
          const SingleActivator(LogicalKeyboardKey.keyK, control: true): () =>
              _select(1),
        },
        child: Focus(
          child: Scaffold(
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
            onSelect: _select,
          ),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(0, 10, 10, 10),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(26),
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: bg.withValues(alpha: isDark ? 0.88 : 0.92),
                    border: Border.all(color: line),
                  ),
                  child: Column(
                    children: [
                      _CommandBar(
                        index: _index,
                        onSearch: () => _select(1),
                        onProfile: () => _select(3),
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
        Align(
          alignment: Alignment.bottomCenter,
          child:
              Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 22),
                    child: Container(
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
                    ),
                  )
                  .animate()
                  .fadeIn(delay: 150.ms)
                  .slideY(begin: 0.6, end: 0, curve: Curves.easeOutBack),
        ),
      ],
    );
  }

  List<_Nav> get _mobileDock => [
    const _Nav(Icons.home_rounded, 'Home', 0),
    const _Nav(Icons.search_rounded, 'Search', 1),
    const _Nav(Icons.favorite_rounded, 'My List', 2),
    const _Nav(Icons.person_rounded, 'Profile', 3),
  ];

  Widget _item(_Nav nav) {
    final sel = nav.page == _index;
    return RemoteTap(
      // The phone dock communicates selection itself. A persistent focus ring
      // made Home look selected after tapping another destination.
      showFocusRing: false,
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
    6 || 7 => live,
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
  _Nav(Icons.calendar_view_week_rounded, 'Guide', 7),
  _Nav(Icons.search_rounded, 'Search', 1),
];

const List<_Nav> _utilityDock = [
  _Nav(Icons.favorite_rounded, 'My List', 2),
  _Nav(Icons.download_rounded, 'Downloads', 8, trailingIsDownloads: true),
  _Nav(Icons.person_rounded, 'Profile', 3),
];

class _SignalDock extends StatelessWidget {
  final int index;
  final _CatalogCapabilities capabilities;
  final ValueChanged<int> onSelect;
  const _SignalDock({
    required this.index,
    required this.capabilities,
    required this.onSelect,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 86,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
        child: Column(
          children: [
            const SizedBox(height: 6),
            Tooltip(message: 'Lumen', child: LumenMark(size: 27)),
            const SizedBox(height: 26),
            for (final nav in _mainDock.where(
              (nav) => capabilities.allows(nav.page),
            ))
              _DockItem(
                nav: nav,
                selected: nav.page == index,
                onTap: () => onSelect(nav.page),
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
  const _DockItem({
    required this.nav,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: nav.label,
      waitDuration: const Duration(milliseconds: 450),
      child: FocusableTap(
        autofocus: nav.page == 0,
        onTap: onTap,
        builder: (context, active) => AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          width: 52,
          height: 44,
          margin: const EdgeInsets.only(bottom: 3),
          decoration: BoxDecoration(
            color: selected
                ? accentInk.withValues(alpha: isDark ? 0.14 : 0.09)
                : (active ? surfaceHi : Colors.transparent),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: selected
                  ? accentInk.withValues(alpha: isDark ? 0.32 : 0.42)
                  : Colors.transparent,
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
                  top: 15,
                  bottom: 15,
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
                  builder: (_, __) {
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
  const _CommandBar({
    required this.index,
    required this.onSearch,
    required this.onProfile,
  });

  static const _titles = <int, String>{
    0: 'Tonight',
    1: 'Search library',
    2: 'My list',
    3: 'Profile',
    4: 'Movies',
    5: 'Series',
    6: 'Live signal',
    7: 'TV guide',
    8: 'Downloads',
  };

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 66,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 22),
        child: Row(
          children: [
            Text(_titles[index] ?? 'Lumen', style: kTitle()),
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
                onTap: onSearch,
                builder: (_, active) => AnimatedContainer(
                  duration: const Duration(milliseconds: 160),
                  width: 236,
                  height: 40,
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                  decoration: BoxDecoration(
                    color: active ? surfaceHi : surface,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: active ? accentInk : line),
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
                      Text(
                        '⌘ K',
                        style: TextStyle(
                          color: subtle,
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 10),
            ],
            IconButton(
              tooltip: 'Refresh library',
              onPressed: () {
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
              icon: Icon(Icons.sync_rounded, color: muted, size: 20),
            ),
            const SizedBox(width: 2),
            FocusableTap(
              onTap: onProfile,
              builder: (_, active) => AnimatedContainer(
                duration: const Duration(milliseconds: 160),
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: active ? accent : surfaceHi,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: active ? accent : line),
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
