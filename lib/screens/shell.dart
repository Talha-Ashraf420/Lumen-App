import 'package:flutter/material.dart';
import '../store.dart';
import '../theme.dart';
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

  static const _titles = ['Live TV', 'Movies', 'Series'];

  @override
  Widget build(BuildContext context) {
    final pages = [
      CatalogScreen(client: widget.client, kind: 'live'),
      CatalogScreen(client: widget.client, kind: 'movie'),
      CatalogScreen(client: widget.client, kind: 'series'),
    ];
    return Scaffold(
      appBar: AppBar(
        title: Text(_titles[_index], style: const TextStyle(fontWeight: FontWeight.bold)),
        actions: [
          IconButton(
            icon: const Icon(Icons.logout_rounded, color: muted),
            tooltip: 'Sign out',
            onPressed: () async {
              await Store.logout();
              widget.onLogout();
            },
          ),
        ],
      ),
      body: IndexedStack(index: _index, children: pages),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (i) => setState(() => _index = i),
        backgroundColor: surface,
        indicatorColor: accent.withValues(alpha: 0.25),
        destinations: const [
          NavigationDestination(icon: Icon(Icons.live_tv_rounded), label: 'Live'),
          NavigationDestination(icon: Icon(Icons.movie_rounded), label: 'Movies'),
          NavigationDestination(icon: Icon(Icons.video_library_rounded), label: 'Series'),
        ],
      ),
    );
  }
}
