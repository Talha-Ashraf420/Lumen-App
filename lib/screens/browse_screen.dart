import 'package:flutter/material.dart';
import '../theme.dart';
import '../widgets.dart';
import '../xtream.dart';
import 'catalog_screen.dart';

/// Browse by section (Live / Movies / Series) with the grid + search + chips.
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
        const Padding(
          padding: EdgeInsets.fromLTRB(20, 6, 20, 12),
          child: Align(
            alignment: Alignment.centerLeft,
            child: Text('Browse', style: TextStyle(fontSize: 26, fontWeight: FontWeight.w800)),
          ),
        ),
        Padding(
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
                        height: 40,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          gradient: i == _index ? accentGradient : null,
                          borderRadius: BorderRadius.circular(13),
                          boxShadow: i == _index ? glow(accent, blur: 14, y: 4, a: 0.5) : null,
                        ),
                        child: Text(_tabs[i].label,
                            style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14, color: i == _index ? Colors.white : muted)),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 10),
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
