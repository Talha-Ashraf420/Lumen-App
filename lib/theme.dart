import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';

// "Lumen" — a flat, single-accent system (no gradients). One refined violet
// accent reads cleanly on both a near-black dark canvas and a soft-white light
// canvas. Surfaces are solid; depth comes from a single neutral shadow.

/// Semantic colour set for one brightness.
class Palette {
  final Color bg;
  final Color surface;
  final Color surfaceHi;
  final Color line;
  final Color textHi; // high-emphasis text / icons (a.k.a. "cream")
  final Color muted; // secondary text
  final Color subtle; // tertiary text / hints
  final Color accent; // single brand accent
  final Color accentDark; // pressed / deeper accent
  final Color gold; // rating highlight
  final Brightness brightness;
  const Palette({
    required this.bg,
    required this.surface,
    required this.surfaceHi,
    required this.line,
    required this.textHi,
    required this.muted,
    required this.subtle,
    required this.accent,
    required this.accentDark,
    required this.gold,
    required this.brightness,
  });
}

const defaultAccent = Color(0xFF22CBA8); // teal

/// A few curated accent presets shown in the picker (plus a custom option).
const accentPresets = <Color>[
  Color(0xFF22CBA8), // teal
  Color(0xFF06B6D4), // cyan
  Color(0xFF3B82F6), // blue
  Color(0xFF6366F1), // indigo
  Color(0xFFA855F7), // purple
  Color(0xFFEC4899), // pink
  Color(0xFFEF4444), // red
  Color(0xFFF97316), // orange
  Color(0xFFF59E0B), // amber
  Color(0xFF22C55E), // green
];

Color _shade(Color c, double dl) {
  final h = HSLColor.fromColor(c);
  return h.withLightness((h.lightness + dl).clamp(0.0, 1.0)).toColor();
}

/// Build a dark palette graded toward the chosen accent's hue — surfaces pick up
/// a subtle tint so the whole UI feels coherent, not just the accent button.
Palette darkPaletteFor(Color a) {
  final h = HSLColor.fromColor(a).hue;
  Color t(double l, double s) => HSLColor.fromAHSL(1, h, s, l).toColor();
  return Palette(
    bg: t(0.055, 0.34),
    surface: t(0.085, 0.26),
    surfaceHi: t(0.135, 0.20),
    line: const Color(0x14FFFFFF),
    textHi: t(0.95, 0.10),
    muted: t(0.66, 0.12),
    subtle: t(0.48, 0.10),
    accent: a,
    accentDark: _shade(a, -0.12),
    gold: const Color(0xFFFFC15E),
    brightness: Brightness.dark,
  );
}

Palette lightPaletteFor(Color a) {
  final h = HSLColor.fromColor(a).hue;
  Color t(double l, double s) => HSLColor.fromAHSL(1, h, s, l).toColor();
  return Palette(
    bg: t(0.965, 0.30),
    surface: const Color(0xFFFFFFFF),
    surfaceHi: t(0.93, 0.22),
    line: const Color(0x14000000),
    textHi: t(0.10, 0.30),
    muted: t(0.40, 0.16),
    subtle: t(0.60, 0.10),
    accent: _shade(a, -0.08),
    accentDark: _shade(a, -0.20),
    gold: const Color(0xFFD9982E),
    brightness: Brightness.light,
  );
}

Palette darkPalette = darkPaletteFor(defaultAccent);
Palette lightPalette = lightPaletteFor(defaultAccent);

/// The palette in effect for the current frame. The root widget assigns this
/// from the resolved brightness before the tree builds, so the existing
/// `bg` / `surface` / `accent` references stay valid without threading context.
Palette activePalette = darkPalette;

bool get isDark => activePalette.brightness == Brightness.dark;

// Theme-aware semantic colours (read the active palette).
Color get bg => activePalette.bg;
Color get surface => activePalette.surface;
Color get surfaceHi => activePalette.surfaceHi;
Color get line => activePalette.line;
Color get cream => activePalette.textHi; // legacy name kept for call sites
Color get textHi => activePalette.textHi;
Color get muted => activePalette.muted;
Color get subtle => activePalette.subtle;
Color get accent => activePalette.accent;
Color get accentDark => activePalette.accentDark;
Color get accent2 => activePalette.accent; // legacy alias → single accent
Color get gold => activePalette.gold;

/// One soft, neutral shadow for floating surfaces (no coloured glow).
List<BoxShadow> glow(Color c, {double blur = 24, double y = 10, double a = 0.0}) => [
      BoxShadow(
        color: Colors.black.withValues(alpha: isDark ? 0.40 : 0.10),
        blurRadius: blur,
        offset: Offset(0, y),
      ),
    ];

// ---- Type scale (elegant, airy) — large light display, refined labels. ----
TextStyle kHero({Color? color}) =>
    GoogleFonts.manrope(fontSize: 56, fontWeight: FontWeight.w300, letterSpacing: -1.0, height: 1.05, color: color ?? textHi);
TextStyle kDisplay({Color? color}) =>
    GoogleFonts.manrope(fontSize: 34, fontWeight: FontWeight.w700, letterSpacing: -0.4, height: 1.08, color: color ?? textHi);
TextStyle kTitle({Color? color}) =>
    GoogleFonts.manrope(fontSize: 22, fontWeight: FontWeight.w700, letterSpacing: -0.2, color: color ?? textHi);
TextStyle kSection({Color? color}) =>
    GoogleFonts.manrope(fontSize: 12.5, fontWeight: FontWeight.w700, letterSpacing: 1.6, color: color ?? muted);
TextStyle kBody({Color? color}) =>
    GoogleFonts.manrope(fontSize: 15, fontWeight: FontWeight.w400, height: 1.6, color: color ?? muted);

ThemeData buildTheme(Palette p) {
  final base = ThemeData(brightness: p.brightness, useMaterial3: true);
  final text = GoogleFonts.manropeTextTheme(base.textTheme).apply(bodyColor: p.textHi, displayColor: p.textHi);
  return base.copyWith(
    scaffoldBackgroundColor: p.bg,
    colorScheme: base.colorScheme.copyWith(
      primary: p.accent,
      secondary: p.accent,
      surface: p.surface,
      surfaceContainerHighest: p.surfaceHi,
      brightness: p.brightness,
    ),
    textTheme: text,
    appBarTheme: AppBarTheme(
      backgroundColor: Colors.transparent,
      elevation: 0,
      scrolledUnderElevation: 0,
      titleTextStyle: GoogleFonts.manrope(fontSize: 22, fontWeight: FontWeight.w800, color: p.textHi),
    ),
    iconTheme: IconThemeData(color: p.textHi),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: p.surfaceHi.withValues(alpha: 0.7),
      hintStyle: TextStyle(color: p.subtle),
      labelStyle: TextStyle(color: p.muted),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide.none),
      enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide(color: p.line)),
      focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide(color: p.accent)),
    ),
  );
}

/// App-wide theme mode (dark / light / system), persisted to prefs.
class ThemeController {
  ThemeController._();
  static final ThemeController instance = ThemeController._();
  static const _key = 'lumen_theme_mode';

  static const _accentKey = 'lumen_accent_color';

  final ValueNotifier<ThemeMode> mode = ValueNotifier(ThemeMode.dark);
  final ValueNotifier<Color> accent = ValueNotifier(defaultAccent);

  /// Rebuild signal for both theme mode and accent changes.
  Listenable get listenable => Listenable.merge([mode, accent]);

  Future<void> load() async {
    final p = await SharedPreferences.getInstance();
    switch (p.getString(_key)) {
      case 'light':
        mode.value = ThemeMode.light;
      case 'system':
        mode.value = ThemeMode.system;
      case 'dark':
        mode.value = ThemeMode.dark;
    }
    final c = p.getInt(_accentKey);
    if (c != null) accent.value = Color(c);
  }

  Future<void> set(ThemeMode m) async {
    mode.value = m;
    final p = await SharedPreferences.getInstance();
    await p.setString(_key, m.name);
  }

  Future<void> setAccent(Color c) async {
    accent.value = c;
    final p = await SharedPreferences.getInstance();
    await p.setInt(_accentKey, c.toARGB32());
  }
}

/// Resolves the active palette for the current mode + platform brightness,
/// assigns the global `activePalette`, and syncs the status-bar icon colour.
Palette resolvePalette(ThemeMode mode, Brightness platform) {
  final wantDark = switch (mode) {
    ThemeMode.dark => true,
    ThemeMode.light => false,
    ThemeMode.system => platform == Brightness.dark,
  };
  final a = ThemeController.instance.accent.value;
  final p = wantDark ? darkPaletteFor(a) : lightPaletteFor(a);
  activePalette = p;
  SystemChrome.setSystemUIOverlayStyle(SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: wantDark ? Brightness.light : Brightness.dark,
    statusBarBrightness: wantDark ? Brightness.dark : Brightness.light,
  ));
  return p;
}
