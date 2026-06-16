import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../theme.dart';
import '../widgets.dart';
import '../xtream.dart';
import 'catalog_screen.dart';

class HomeShell extends StatefulWidget {
  final XtreamClient client;
  final VoidCallback onLogout;
  const HomeShell({super.key, required this.client, required this.onLogout});
  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int _index = 0;

  static const _tabs = [
    (label: 'Live', icon: Icons.sensors_rounded, kind: 'live'),
    (label: 'Movies', icon: Icons.theaters_rounded, kind: 'movie'),
    (label: 'Series', icon: Icons.grid_view_rounded, kind: 'series'),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      extendBody: true,
      body: Stack(
        children: [
          const Aurora(),
          SafeArea(
            bottom: false,
            child: Column(
              children: [
                _TopBar(onLogout: widget.onLogout),
                Expanded(
                  child: IndexedStack(
                    index: _index,
                    children: [
                      for (final t in _tabs) CatalogScreen(client: widget.client, kind: t.kind),
                    ],
                  ),
                ),
              ],
            ),
          ),
          // floating glass nav
          Align(
            alignment: Alignment.bottomCenter,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(28, 0, 28, 24),
              child: Glass(
                radius: 28,
                blur: 24,
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [for (var i = 0; i < _tabs.length; i++) _navItem(i)],
                ),
              ),
            ).animate().fadeIn(delay: 150.ms).slideY(begin: 0.4, end: 0, curve: Curves.easeOutBack),
          ),
        ],
      ),
    );
  }

  Widget _navItem(int i) {
    final t = _tabs[i];
    final sel = i == _index;
    return GestureDetector(
      onTap: () => setState(() => _index = i),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOut,
        padding: EdgeInsets.symmetric(horizontal: sel ? 18 : 14, vertical: 11),
        decoration: BoxDecoration(
          gradient: sel ? accentGradient : null,
          borderRadius: BorderRadius.circular(20),
          boxShadow: sel ? glow(accent, blur: 18, y: 6, a: 0.5) : null,
        ),
        child: Row(
          children: [
            Icon(t.icon, size: 20, color: sel ? Colors.white : muted),
            if (sel) ...[
              const SizedBox(width: 8),
              Text(t.label, style: const TextStyle(fontWeight: FontWeight.w700, color: Colors.white)),
            ],
          ],
        ),
      ),
    );
  }
}

class _TopBar extends StatelessWidget {
  final VoidCallback onLogout;
  const _TopBar({required this.onLogout});
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 14, 12, 6),
      child: Row(
        children: [
          ShaderMask(
            shaderCallback: (r) => accentGradient.createShader(r),
            child: const Text('Lumen',
                style: TextStyle(
                    fontSize: 26, fontWeight: FontWeight.w800, color: Colors.white, letterSpacing: -0.5)),
          ),
          const Spacer(),
          IconButton(
            onPressed: onLogout,
            icon: const Icon(Icons.logout_rounded, color: muted, size: 22),
            tooltip: 'Sign out',
          ),
        ],
      ),
    );
  }
}
