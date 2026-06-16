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
    (label: 'Live TV', kind: 'live'),
    (label: 'Movies', kind: 'movie'),
    (label: 'Series', kind: 'series'),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          const Aurora(),
          SafeArea(
            bottom: false,
            child: Column(
              children: [
                _header(),
                _segmentedTabs(),
                const SizedBox(height: 10),
                Expanded(
                  child: IndexedStack(
                    index: _index,
                    children: [for (final t in _tabs) CatalogScreen(client: widget.client, kind: t.kind)],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _header() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 12, 12),
      child: Row(
        children: [
          ShaderMask(
            shaderCallback: (r) => accentGradient.createShader(r),
            child: const Text('Lumen',
                style: TextStyle(fontSize: 28, fontWeight: FontWeight.w800, color: Colors.white, letterSpacing: -0.6)),
          ),
          const Spacer(),
          IconButton(
            onPressed: widget.onLogout,
            icon: const Icon(Icons.logout_rounded, color: muted, size: 22),
            tooltip: 'Sign out',
          ),
        ],
      ),
    );
  }

  Widget _segmentedTabs() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Glass(
        radius: 18,
        blur: 16,
        padding: const EdgeInsets.all(5),
        child: Row(
          children: [
            for (var i = 0; i < _tabs.length; i++)
              Expanded(
                child: GestureDetector(
                  onTap: () => setState(() => _index = i),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 250),
                    curve: Curves.easeOut,
                    height: 40,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      gradient: i == _index ? accentGradient : null,
                      borderRadius: BorderRadius.circular(13),
                      boxShadow: i == _index ? glow(accent, blur: 14, y: 4, a: 0.5) : null,
                    ),
                    child: Text(
                      _tabs[i].label,
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 14,
                        color: i == _index ? Colors.white : muted,
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    ).animate().fadeIn(duration: 350.ms).slideY(begin: -0.3, end: 0, curve: Curves.easeOut);
  }
}
