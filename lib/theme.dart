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

const _accent = Color(0xFF7C6BFF); // shared brand accent

const darkPalette = Palette(
  bg: Color(0xFF0C0A12),
  surface: Color(0xFF15131C),
  surfaceHi: Color(0xFF1F1C28),
  line: Color(0x14FFFFFF),
  textHi: Color(0xFFF4F2F8),
  muted: Color(0xFFA8A2B5),
  subtle: Color(0xFF6E6980),
  accent: Color(0xFF8B7BFF),
  accentDark: Color(0xFF6B5BE0),
  gold: Color(0xFFFFC15E),
  brightness: Brightness.dark,
);

const lightPalette = Palette(
  bg: Color(0xFFFBFBFD),
  surface: Color(0xFFFFFFFF),
  surfaceHi: Color(0xFFF1F0F5),
  line: Color(0x14000000),
  textHi: Color(0xFF15131C),
  muted: Color(0xFF6B6676),
  subtle: Color(0xFF9D97A8),
  accent: Color(0xFF6C5CE7),
  accentDark: Color(0xFF5546C9),
  gold: Color(0xFFD9982E),
  brightness: Brightness.light,
);

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

  final ValueNotifier<ThemeMode> mode = ValueNotifier(ThemeMode.dark);

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
  }

  Future<void> set(ThemeMode m) async {
    mode.value = m;
    final p = await SharedPreferences.getInstance();
    await p.setString(_key, m.name);
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
  final p = wantDark ? darkPalette : lightPalette;
  activePalette = p;
  SystemChrome.setSystemUIOverlayStyle(SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: wantDark ? Brightness.light : Brightness.dark,
    statusBarBrightness: wantDark ? Brightness.dark : Brightness.light,
  ));
  return p;
}
