import 'package:flutter/material.dart';

// "Ember Noir" — warm obsidian + coral→amber accent. A distinct, premium
// identity for the mobile app (the web app uses cool periwinkle/mint).
const bg = Color(0xFF0B0A09); // warm near-black
const surface = Color(0xFF15120F);
const surfaceHi = Color(0xFF211B15);
const line = Color(0x14FFFFFF);
const muted = Color(0xFFB3A99C);
const subtle = Color(0xFF73695C);
const cream = Color(0xFFF7F1E9);
const accent = Color(0xFFFF7A52); // coral / ember
const accentDark = Color(0xFFE85C34);
const accent2 = Color(0xFFFFB454); // amber

const accentGradient = LinearGradient(
  begin: Alignment.topLeft,
  end: Alignment.bottomRight,
  colors: [accent, accent2],
);

ThemeData buildTheme() {
  final base = ThemeData.dark(useMaterial3: true);
  return base.copyWith(
    scaffoldBackgroundColor: bg,
    colorScheme: base.colorScheme.copyWith(
      primary: accent,
      secondary: accent2,
      surface: surface,
      surfaceContainerHighest: surfaceHi,
    ),
    textTheme: base.textTheme.apply(bodyColor: cream, displayColor: cream),
    appBarTheme: const AppBarTheme(backgroundColor: Colors.transparent, elevation: 0, scrolledUnderElevation: 0),
    iconTheme: const IconThemeData(color: cream),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: surfaceHi,
      hintStyle: const TextStyle(color: subtle),
      labelStyle: const TextStyle(color: muted),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
      enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: line)),
      focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: accent)),
    ),
  );
}
