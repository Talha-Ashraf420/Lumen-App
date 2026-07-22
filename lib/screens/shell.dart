import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
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
import 'globe_screen.dart';
import 'home_screen.dart';
import 'update_dialog.dart';
import 'mylist_screen.dart';
import 'profile_screen.dart';
import 'search_screen.dart';

class HomeShell extends StatefulWidget {
  final XtreamClient client;
  final VoidCallback onLogout;
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
  // Auto-refresh the catalog when the app returns to the foreground (throttled),
  // so recently-added movies surface without a manual Refresh.
  DateTime _lastRefresh = DateTime.now();
  // Tabs initialise only once first opened — avoids a startup request burst
  // (e.g. the Live guide loading EPG) that can trip the provider.
  final Set<int> _visited = {0};

  // Total destinations (mobile shows 0–4; desktop sidebar adds Movies/Series/
  // Live/TV-Guide/Downloads = 5/6/7/8/9 — see _pageFor and _Sidebar).
  static const _pageCount = 10;

  // Mobile bottom-nav tabs (indices 0–4).
  static const _nav = [
    (icon: Icons.home_rounded, label: 'Home'),
    (icon: Icons.auto_awesome_rounded, label: 'Discover'),
    (icon: Icons.search_rounded, label: 'Search'),
    (icon: Icons.favorite_rounded, label: 'My List'),
    (icon: Icons.person_rounded, label: 'Profile'),
  ];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // Quietly check for a newer build once per launch (skip dev builds).
    if (kBuildNumber > 0) {
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        final result = await Updater.instance.check();
        if (result.status == UpdateCheckStatus.available && mounted) {
          showUpdateFlow(context, result.info!);
        }
      });
    }
  }

  @override
  void dispose() {
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
    // Throttle: only re-fetch if it's been a few minutes since the last refresh.
    if (now.difference(_lastRefresh) > const Duration(minutes: 3)) {
      _lastRefresh = now;
      refreshContent();
    }
  }

  Widget _pageFor(int i) => switch (i) {
    0 => HomeScreen(client: widget.client, onBrowse: () => _select(2)),
    1 => GlobeScreen(client: widget.client),
    2 => SearchScreen(client: widget.client),
    3 => MyListScreen(client: widget.client),
    4 => ProfileScreen(
      client: widget.client,
      onLogout: widget.onLogout,
      onSwitch: widget.onSwitch,
    ),
    5 => SearchScreen(client: widget.client, initialSection: 'movie'),
    6 => SearchScreen(client: widget.client, initialSection: 'series'),
    7 => SearchScreen(client: widget.client, initialSection: 'live'),
    8 => EpgGuideScreen(client: widget.client),
    _ => DownloadsScreen(client: widget.client),
  };

  void _select(int i) {
    if (i != _index) HapticFeedback.selectionClick();
    setState(() => _index = i);
  }

  @override
  Widget build(BuildContext context) {
    _visited.add(_index);
    final pages = [
      for (var i = 0; i < _pageCount; i++)
        _visited.contains(i) ? _pageFor(i) : const SizedBox.shrink(),
    ];
    final wide = isWide(context);
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.keyK, meta: true): () =>
            _select(2),
        const SingleActivator(LogicalKeyboardKey.keyK, control: true): () =>
            _select(2),
      },
      child: Focus(
        autofocus: true,
        child: Scaffold(
          body: Stack(
            children: [
              Aurora(),
              if (wide) _wideLayout(pages) else _mobileLayout(pages),
            ],
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
          _SignalDock(index: _index, onSelect: _select),
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
                        onSearch: () => _select(2),
                        onProfile: () => _select(4),
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
                        children: [
                          for (var i = 0; i < _nav.length; i++) _item(i),
                        ],
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

  Widget _item(int i) {
    final sel = i == _index;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => _select(i),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 280),
        curve: Curves.easeOut,
        margin: const EdgeInsets.symmetric(horizontal: 2),
        padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 8),
        decoration: BoxDecoration(
          color: sel ? accent.withValues(alpha: 0.12) : null,
          borderRadius: BorderRadius.circular(17),
          border: sel
              ? Border.all(color: accent.withValues(alpha: 0.28))
              : null,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(_nav[i].icon, size: 20, color: sel ? accent : muted),
            const SizedBox(height: 3),
            Text(
              _nav[i].label,
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
  _Nav(Icons.blur_circular_rounded, 'Discover', 1),
  _Nav(Icons.movie_filter_rounded, 'Movies', 5),
  _Nav(Icons.amp_stories_rounded, 'Series', 6),
  _Nav(Icons.sensors_rounded, 'Live', 7),
  _Nav(Icons.calendar_view_week_rounded, 'Guide', 8),
  _Nav(Icons.search_rounded, 'Search', 2),
];

const List<_Nav> _utilityDock = [
  _Nav(Icons.favorite_rounded, 'My List', 3),
  _Nav(Icons.download_rounded, 'Downloads', 9, trailingIsDownloads: true),
  _Nav(Icons.person_rounded, 'Profile', 4),
];

class _SignalDock extends StatelessWidget {
  final int index;
  final ValueChanged<int> onSelect;
  const _SignalDock({required this.index, required this.onSelect});

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
            for (final nav in _mainDock)
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
        onTap: onTap,
        builder: (context, active) => AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          width: 52,
          height: 44,
          margin: const EdgeInsets.only(bottom: 3),
          decoration: BoxDecoration(
            color: selected
                ? accent.withValues(alpha: 0.14)
                : (active ? surfaceHi : Colors.transparent),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: selected
                  ? accent.withValues(alpha: 0.32)
                  : Colors.transparent,
            ),
          ),
          child: Stack(
            children: [
              Center(
                child: Icon(
                  nav.icon,
                  size: 21,
                  color: selected ? accent : (active ? textHi : muted),
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
                      color: accent,
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
                                color: accent,
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
    1: 'Discover',
    2: 'Search',
    3: 'My list',
    4: 'Profile',
    5: 'Movies',
    6: 'Series',
    7: 'Live signal',
    8: 'TV guide',
    9: 'Downloads',
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
              decoration: BoxDecoration(color: accent, shape: BoxShape.circle),
            ),
            const Spacer(),
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
                  border: Border.all(color: active ? accent : line),
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
