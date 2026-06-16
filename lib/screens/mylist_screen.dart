import 'package:flutter/material.dart';
import '../theme.dart';

class MyListScreen extends StatelessWidget {
  const MyListScreen({super.key});
  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        const Padding(
          padding: EdgeInsets.fromLTRB(20, 6, 20, 12),
          child: Align(
            alignment: Alignment.centerLeft,
            child: Text('My List', style: TextStyle(fontSize: 26, fontWeight: FontWeight.w800)),
          ),
        ),
        Expanded(
          child: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  padding: const EdgeInsets.all(22),
                  decoration: BoxDecoration(color: surfaceHi.withValues(alpha: 0.6), shape: BoxShape.circle),
                  child: const Icon(Icons.favorite_rounded, color: accent, size: 34),
                ),
                const SizedBox(height: 16),
                const Text('Nothing saved yet', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
                const SizedBox(height: 6),
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 50),
                  child: Text('Tap the heart on any movie or series to keep it here.',
                      textAlign: TextAlign.center, style: TextStyle(color: subtle, height: 1.4)),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
