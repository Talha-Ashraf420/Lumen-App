import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

// "Nebula" — deep charcoal-violet base with a signature violet→fuchsia gradient
// and a warm gold highlight. Premium, expressive, distinct from the web app.
const bg = Color(0xFF0C0A12); // charcoal-violet near-black
const surface = Color(0xFF15121E);
const surfaceHi = Color(0xFF1E1A2B);
const line = Color(0x14FFFFFF);
const muted = Color(0xFFAAA2BE);
const subtle = Color(0xFF6E6680);
const cream = Color(0xFFFAFAFA);
const accent = Color(0xFF8B5CFF); // violet
const accentDark = Color(0xFF6B3FE0);
const accent2 = Color(0xFFFF5DA2); // fuchsia
const gold = Color(0xFFFFC15E); // ratings highlight

// signature gradient (violet → fuchsia)
const accentGradient = LinearGradient(
  begin: Alignment.topLeft,
  end: Alignment.bottomRight,
  colors: [accent, accent2],
);

// soft glow shadow for floating/premium surfaces
List<BoxShadow> glow(Color c, {double blur = 28, double y = 10, double a = 0.45}) =>
    [BoxShadow(color: c.withValues(alpha: a), blurRadius: blur, offset: Offset(0, y))];

ThemeData buildTheme() {
  final base = ThemeData.dark(useMaterial3: true);
  final text = GoogleFonts.manropeTextTheme(base.textTheme).apply(bodyColor: cream, displayColor: cream);
  return base.copyWith(
    scaffoldBackgroundColor: bg,
    colorScheme: base.colorScheme.copyWith(
      primary: accent,
      secondary: accent2,
      surface: surface,
      surfaceContainerHighest: surfaceHi,
    ),
    textTheme: text,
    appBarTheme: AppBarTheme(
      backgroundColor: Colors.transparent,
      elevation: 0,
      scrolledUnderElevation: 0,
      titleTextStyle: GoogleFonts.manrope(fontSize: 22, fontWeight: FontWeight.w800, color: cream),
    ),
    iconTheme: const IconThemeData(color: cream),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: surfaceHi.withValues(alpha: 0.7),
      hintStyle: const TextStyle(color: subtle),
      labelStyle: const TextStyle(color: muted),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide.none),
      enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16), borderSide: const BorderSide(color: line)),
      focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16), borderSide: const BorderSide(color: accent)),
    ),
  );
}
