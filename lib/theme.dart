import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';

// Lumen's "night cinema" system. The canvas stays neutral so artwork remains
// the loudest thing on screen; the user-selected accent behaves like a small
// signal light instead of tinting every surface.

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

const defaultAccent = Color(0xFFC7F36B); // signal lime

/// A few curated accent presets shown in the picker (plus a custom option).
const accentPresets = <Color>[
  Color(0xFFC7F36B), // signal lime
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

/// Neutral cinema blacks keep wildly different provider artwork coherent.
Palette darkPaletteFor(Color a) {
  return Palette(
    bg: const Color(0xFF080A0B),
    surface: const Color(0xFF101315),
    surfaceHi: const Color(0xFF181C1F),
    line: const Color(0x18FFFFFF),
    textHi: const Color(0xFFF4F1E8),
    muted: const Color(0xFFA2A6A3),
    subtle: const Color(0xFF686E6A),
    accent: a,
    accentDark: _shade(a, -0.12),
    gold: const Color(0xFFFFC15E),
    brightness: Brightness.dark,
  );
}

Palette lightPaletteFor(Color a) {
  return Palette(
    bg: const Color(0xFFF1F0EA),
    surface: const Color(0xFFFAF9F4),
    surfaceHi: const Color(0xFFE7E6DF),
    line: const Color(0x14000000),
    textHi: const Color(0xFF111310),
    muted: const Color(0xFF555A55),
    subtle: const Color(0xFF858A84),
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
Color get onAccent => ThemeData.estimateBrightnessForColor(accent) == Brightness.light
    ? const Color(0xFF11130F)
    : Colors.white;

/// One soft, neutral shadow for floating surfaces (no coloured glow).
List<BoxShadow> glow(Color c, {double blur = 24, double y = 10, double a = 0.0}) => [
      BoxShadow(
        color: Colors.black.withValues(alpha: isDark ? 0.40 : 0.10),
        blurRadius: blur,
        offset: Offset(0, y),
      ),
    ];

// Space Grotesk gives the interface a compact editorial rhythm without making
// long metadata or settings text feel ornamental.
TextStyle kHero({Color? color}) =>
    GoogleFonts.spaceGrotesk(fontSize: 62, fontWeight: FontWeight.w500, letterSpacing: -2.4, height: 0.98, color: color ?? textHi);
TextStyle kDisplay({Color? color}) =>
    GoogleFonts.spaceGrotesk(fontSize: 38, fontWeight: FontWeight.w600, letterSpacing: -1.2, height: 1.02, color: color ?? textHi);
TextStyle kTitle({Color? color}) =>
    GoogleFonts.spaceGrotesk(fontSize: 23, fontWeight: FontWeight.w600, letterSpacing: -0.6, color: color ?? textHi);
TextStyle kSection({Color? color}) =>
    GoogleFonts.spaceGrotesk(fontSize: 11.5, fontWeight: FontWeight.w600, letterSpacing: 1.8, color: color ?? muted);
TextStyle kBody({Color? color}) =>
    GoogleFonts.spaceGrotesk(fontSize: 15, fontWeight: FontWeight.w400, height: 1.55, color: color ?? muted);

ThemeData buildTheme(Palette p) {
  final base = ThemeData(brightness: p.brightness, useMaterial3: true);
  final text = GoogleFonts.spaceGroteskTextTheme(base.textTheme).apply(bodyColor: p.textHi, displayColor: p.textHi);
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
      titleTextStyle: GoogleFonts.spaceGrotesk(fontSize: 22, fontWeight: FontWeight.w600, color: p.textHi, letterSpacing: -0.5),
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
    dividerTheme: DividerThemeData(color: p.line, thickness: 1),
    splashColor: p.accent.withValues(alpha: 0.08),
    highlightColor: p.accent.withValues(alpha: 0.05),
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
