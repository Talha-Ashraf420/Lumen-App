import 'package:flutter/material.dart';
import '../theme.dart';
import '../xtream.dart';
import 'catalog_screen.dart';

/// Browse by section (Live / Movies / Series) using clean minimal text tabs.
class BrowseScreen extends StatefulWidget {
  final XtreamClient client;
  const BrowseScreen({super.key, required this.client});
  @override
  State<BrowseScreen> createState() => _BrowseScreenState();
}

class _BrowseScreenState extends State<BrowseScreen> {
  int _index = 0;
  static const _tabs = [(label: 'Live TV', kind: 'live'), (label: 'Movies', kind: 'movie'), (label: 'Series', kind: 'series')];

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        SizedBox(
          height: 52,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.fromLTRB(20, 6, 20, 0),
            itemCount: _tabs.length,
            separatorBuilder: (_, __) => const SizedBox(width: 22),
            itemBuilder: (_, i) {
              final sel = i == _index;
              return GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => setState(() => _index = i),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    AnimatedDefaultTextStyle(
                      duration: const Duration(milliseconds: 200),
                      style: TextStyle(
                        fontSize: sel ? 24 : 19,
                        fontWeight: sel ? FontWeight.w800 : FontWeight.w600,
                        color: sel ? cream : subtle,
                        letterSpacing: -0.4,
                      ),
                      child: Text(_tabs[i].label),
                    ),
                    const SizedBox(height: 5),
                    AnimatedContainer(
                      duration: const Duration(milliseconds: 220),
                      height: 3,
                      width: sel ? 22 : 0,
                      decoration: BoxDecoration(gradient: accentGradient, borderRadius: BorderRadius.circular(3)),
                    ),
                  ],
                ),
              );
            },
          ),
        ),
        const SizedBox(height: 8),
        Expanded(
          child: IndexedStack(
            index: _index,
            children: [for (final t in _tabs) CatalogScreen(client: widget.client, kind: t.kind)],
          ),
        ),
      ],
    );
  }
}
