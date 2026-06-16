import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../theme.dart';
import '../widgets.dart';
import '../xtream.dart';
import 'browse_screen.dart';
import 'home_screen.dart';
import 'mylist_screen.dart';
import 'profile_screen.dart';

class HomeShell extends StatefulWidget {
  final XtreamClient client;
  final VoidCallback onLogout;
  const HomeShell({super.key, required this.client, required this.onLogout});
  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int _index = 0;

  static const _nav = [
    (icon: Icons.home_rounded, label: 'Home'),
    (icon: Icons.search_rounded, label: 'Browse'),
    (icon: Icons.favorite_rounded, label: 'My List'),
    (icon: Icons.person_rounded, label: 'Profile'),
  ];

  @override
  Widget build(BuildContext context) {
    final pages = [
      HomeScreen(client: widget.client, onBrowse: () => setState(() => _index = 1)),
      BrowseScreen(client: widget.client),
      const MyListScreen(),
      ProfileScreen(client: widget.client, onLogout: widget.onLogout),
    ];
    return Scaffold(
      body: Stack(
        children: [
          const Aurora(),
          SafeArea(bottom: false, child: IndexedStack(index: _index, children: pages)),
          Align(
            alignment: Alignment.bottomCenter,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(40, 0, 40, 22),
              child: Glass(
                radius: 30,
                blur: 26,
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [for (var i = 0; i < _nav.length; i++) _item(i)],
                ),
              ),
            ).animate().fadeIn(delay: 150.ms).slideY(begin: 0.6, end: 0, curve: Curves.easeOutBack),
          ),
        ],
      ),
    );
  }

  Widget _item(int i) {
    final sel = i == _index;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => setState(() => _index = i),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 280),
        curve: Curves.easeOut,
        margin: const EdgeInsets.symmetric(horizontal: 3),
        padding: EdgeInsets.symmetric(horizontal: sel ? 16 : 14, vertical: 11),
        decoration: BoxDecoration(
          gradient: sel ? accentGradient : null,
          borderRadius: BorderRadius.circular(18),
          boxShadow: sel ? glow(accent, blur: 16, y: 5, a: 0.55) : null,
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
