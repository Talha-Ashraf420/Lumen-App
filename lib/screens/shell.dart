import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../models.dart';
import '../responsive.dart';
import '../theme.dart';
import '../widgets.dart';
import '../xtream.dart';
import 'globe_screen.dart';
import 'home_screen.dart';
import 'mylist_screen.dart';
import 'profile_screen.dart';
import 'search_screen.dart';

class HomeShell extends StatefulWidget {
  final XtreamClient client;
  final VoidCallback onLogout;
  final void Function(XtreamCredentials) onSwitch;
  const HomeShell({super.key, required this.client, required this.onLogout, required this.onSwitch});
  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int _index = 0;
  // Tabs initialise only once first opened — avoids a startup request burst
  // (e.g. the Live guide loading EPG) that can trip the provider.
  final Set<int> _visited = {0};

  static const _nav = [
    (icon: Icons.home_rounded, label: 'Home'),
    (icon: Icons.auto_awesome_rounded, label: 'Discover'),
    (icon: Icons.search_rounded, label: 'Search'),
    (icon: Icons.favorite_rounded, label: 'My List'),
    (icon: Icons.person_rounded, label: 'Profile'),
  ];

  Widget _pageFor(int i) => switch (i) {
        0 => HomeScreen(client: widget.client, onBrowse: () => _select(2)),
        1 => GlobeScreen(client: widget.client),
        2 => SearchScreen(client: widget.client),
        3 => MyListScreen(client: widget.client),
        _ => ProfileScreen(client: widget.client, onLogout: widget.onLogout, onSwitch: widget.onSwitch),
      };

  void _select(int i) {
    if (i != _index) HapticFeedback.selectionClick();
    setState(() => _index = i);
  }

  @override
  Widget build(BuildContext context) {
    _visited.add(_index);
    final pages = [
      for (var i = 0; i < _nav.length; i++)
        _visited.contains(i) ? _pageFor(i) : const SizedBox.shrink(),
    ];
    final wide = isWide(context);
    return Scaffold(
      body: Stack(
        children: [
          Aurora(),
          if (wide) _wideLayout(pages) else _mobileLayout(pages),
        ],
      ),
    );
  }

  // ---- desktop: left sidebar + centered content ----
  Widget _wideLayout(List<Widget> pages) {
    return Row(
      children: [
        _Sidebar(nav: _nav, index: _index, onSelect: _select),
        Expanded(
          child: SafeArea(
            child: Align(
              alignment: Alignment.topCenter,
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: kMaxContent),
                child: IndexedStack(index: _index, children: pages),
              ),
            ),
          ),
        ),
      ],
    );
  }

  // ---- mobile: floating bottom nav ----
  Widget _mobileLayout(List<Widget> pages) {
    return Stack(
      children: [
        SafeArea(bottom: false, child: IndexedStack(index: _index, children: pages)),
        Align(
          alignment: Alignment.bottomCenter,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 22),
            child: Glass(
              radius: 30,
              blur: 26,
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 9),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [for (var i = 0; i < _nav.length; i++) _item(i)],
              ),
            ),
          ).animate().fadeIn(delay: 150.ms).slideY(begin: 0.6, end: 0, curve: Curves.easeOutBack),
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
        padding: EdgeInsets.symmetric(horizontal: sel ? 14 : 11, vertical: 11),
        decoration: BoxDecoration(
          color: sel ? accent : null,
          borderRadius: BorderRadius.circular(18),
        ),
        child: Row(
          children: [
            Icon(_nav[i].icon, size: 21, color: sel ? Colors.white : muted),
            if (sel) ...[
              const SizedBox(width: 7),
              Text(_nav[i].label, style: const TextStyle(fontWeight: FontWeight.w700, color: Colors.white, fontSize: 13)),
            ],
          ],
        ),
      ),
    );
  }
}

/// Desktop left navigation sidebar.
class _Sidebar extends StatelessWidget {
  final List<({IconData icon, String label})> nav;
  final int index;
  final ValueChanged<int> onSelect;
  const _Sidebar({required this.nav, required this.index, required this.onSelect});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 228,
      decoration: BoxDecoration(
        color: surface.withValues(alpha: 0.55),
        border: Border(right: BorderSide(color: line)),
      ),
      child: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(22, 22, 20, 22),
              child: Wordmark(size: 26),
            ),
            for (var i = 0; i < nav.length; i++)
              _RailItem(icon: nav[i].icon, label: nav[i].label, selected: i == index, onTap: () => onSelect(i)),
            const Spacer(),
          ],
        ),
      ),
    );
  }
}

class _RailItem extends StatefulWidget {
  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;
  const _RailItem({required this.icon, required this.label, required this.selected, required this.onTap});
  @override
  State<_RailItem> createState() => _RailItemState();
}

class _RailItemState extends State<_RailItem> {
  bool _hover = false;
  @override
  Widget build(BuildContext context) {
    final sel = widget.selected;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 3),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            color: sel ? accent : (_hover ? surfaceHi.withValues(alpha: 0.7) : Colors.transparent),
            borderRadius: BorderRadius.circular(14),
          ),
          child: Row(
            children: [
              Icon(widget.icon, size: 21, color: sel ? Colors.white : muted),
              const SizedBox(width: 14),
              Text(widget.label,
                  style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14, color: sel ? Colors.white : textHi)),
            ],
          ),
        ),
      ),
    );
  }
}
