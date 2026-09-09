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
  final Color accentInk; // accessible accent for text/icons on neutral surfaces
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
    required this.accentInk,
    required this.accentDark,
    required this.gold,
    required this.brightness,
  });
}

const defaultAccent = Color(0xFFC7F36B); // signal lime

// Shared geometry and motion keep the interface feeling designed as one
// system. TV focus transitions stay short enough to remain responsive.
const lumenRadiusSm = 12.0;
const lumenRadiusMd = 16.0;
const lumenRadiusLg = 24.0;
const lumenMotionFast = Duration(milliseconds: 140);
const lumenMotion = Duration(milliseconds: 190);

/// Offline-safe type choices designed for both ten-foot TV interfaces and
/// handheld screens. The device option deliberately has no family so Flutter
/// uses the platform's native UI font.
enum LumenFont {
  lumen('Lumen', 'SpaceGrotesk', 'Cinematic and compact'),
  inter('Inter', 'Inter', 'Clean and highly readable'),
  device('Device', null, 'Use the system font');

  const LumenFont(this.label, this.family, this.description);

  final String label;
  final String? family;
  final String description;
}

/// A named, deliberately small set of polished Lumen accents. Keeping this to
/// five avoids the "rainbow picker" look and makes each choice feel like a
/// complete visual direction rather than a random colour.
class AccentScheme {
  final String name;
  final Color color;

  const AccentScheme(this.name, this.color);
}

const accentSchemes = <AccentScheme>[
  AccentScheme('Signal lime', Color(0xFFC7F36B)),
  AccentScheme('Tidal teal', Color(0xFF24C7B0)),
  AccentScheme('Electric blue', Color(0xFF4E7DFF)),
  AccentScheme('Ultraviolet', Color(0xFFA66BFF)),
  AccentScheme('Solar gold', Color(0xFFFFB84D)),
];

/// Colour values remain public for persistence, contrast tests and custom
/// colour detection. The profile UI presents [accentSchemes] by name.
const accentPresets = <Color>[
  Color(0xFFC7F36B), // signal lime
  Color(0xFF24C7B0), // tidal teal
  Color(0xFF4E7DFF), // electric blue
  Color(0xFFA66BFF), // ultraviolet
  Color(0xFFFFB84D), // solar gold
];

Color _shade(Color c, double dl) {
  final h = HSLColor.fromColor(c);
  return h.withLightness((h.lightness + dl).clamp(0.0, 1.0)).toColor();
}

double contrastRatio(Color foreground, Color background) {
  final lighter = foreground.computeLuminance() > background.computeLuminance()
      ? foreground.computeLuminance()
      : background.computeLuminance();
  final darker = foreground.computeLuminance() > background.computeLuminance()
      ? background.computeLuminance()
      : foreground.computeLuminance();
  return (lighter + 0.05) / (darker + 0.05);
}

/// Highest-contrast content colour for a solid accent fill.
Color foregroundFor(Color background) {
  const darkInk = Color(0xFF000000);
  const lightInk = Color(0xFFFFFFFF);
  return contrastRatio(darkInk, background) >=
          contrastRatio(lightInk, background)
      ? darkInk
      : lightInk;
}

/// Preserve the selected hue while moving its lightness only as far as needed
/// to reach WCAG AA contrast against the app's neutral surfaces.
Color _accessibleInk(Color brand, Color background) {
  if (contrastRatio(brand, background) >= 4.5) return brand;
  final hsl = HSLColor.fromColor(brand);
  final darkSurface =
      ThemeData.estimateBrightnessForColor(background) == Brightness.dark;
  for (var step = 1; step <= 24; step++) {
    final amount = step / 24;
    final target = darkSurface ? 1.0 : 0.0;
    final lightness = hsl.lightness + (target - hsl.lightness) * amount;
    final candidate = hsl.withLightness(lightness).toColor();
    if (contrastRatio(candidate, background) >= 4.5) return candidate;
  }
  return foregroundFor(background);
}

/// Neutral cinema blacks keep wildly different provider artwork coherent.
Palette darkPaletteFor(Color a) {
  const neutralSurface = Color(0xFF101315);
  const hardestNeutral = Color(0xFF181C1F);
  return Palette(
    bg: const Color(0xFF080A0B),
    surface: neutralSurface,
    surfaceHi: const Color(0xFF181C1F),
    line: const Color(0x2EFFFFFF),
    textHi: const Color(0xFFF4F1E8),
    muted: _accessibleInk(const Color(0xFFA2A6A3), hardestNeutral),
    subtle: _accessibleInk(const Color(0xFF686E6A), hardestNeutral),
    accent: a,
    accentInk: _accessibleInk(a, hardestNeutral),
    accentDark: _shade(a, -0.12),
    gold: const Color(0xFFFFC15E),
    brightness: Brightness.dark,
  );
}

Palette lightPaletteFor(Color a) {
  const neutralSurface = Color(0xFFFAF9F4);
  const hardestNeutral = Color(0xFFE7E6DF);
  final fill = _shade(a, -0.08);
  return Palette(
    bg: const Color(0xFFF1F0EA),
    surface: neutralSurface,
    surfaceHi: const Color(0xFFE7E6DF),
    line: const Color(0x26000000),
    textHi: const Color(0xFF111310),
    muted: _accessibleInk(const Color(0xFF555A55), hardestNeutral),
    subtle: _accessibleInk(const Color(0xFF858A84), hardestNeutral),
    accent: fill,
    accentInk: _accessibleInk(fill, hardestNeutral),
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
Color get accentInk => activePalette.accentInk;
Color get accentDark => activePalette.accentDark;
Color get accent2 => activePalette.accent; // legacy alias → single accent
Color get gold => activePalette.gold;
Color get onAccent => foregroundFor(accent);
Color get dangerInk =>
    isDark ? const Color(0xFFFF7A9A) : const Color(0xFFA5193C);
Color get surfaceRaised => Color.alphaBlend(
  (isDark ? Colors.white : Colors.white).withValues(
    alpha: isDark ? 0.045 : 0.42,
  ),
  surfaceHi,
);
Color get lineStrong =>
    Color.alphaBlend(accentInk.withValues(alpha: isDark ? 0.18 : 0.24), line);

/// One soft, neutral shadow for floating surfaces (no coloured glow).
List<BoxShadow> glow(
  Color c, {
  double blur = 24,
  double y = 10,
  double a = 0.0,
}) => [
  BoxShadow(
    color: Colors.black.withValues(alpha: isDark ? 0.40 : 0.10),
    blurRadius: blur,
    offset: Offset(0, y),
  ),
];

String? get activeFontFamily => ThemeController.instance.font.value.family;

TextStyle _appFontStyle(TextStyle style) {
  final selected = ThemeController.instance.font.value;
  if (selected == LumenFont.lumen) {
    return GoogleFonts.spaceGrotesk(textStyle: style);
  }
  return style.copyWith(fontFamily: selected.family);
}

TextStyle kHero({Color? color}) => _appFontStyle(
  TextStyle(
    fontSize: 62,
    fontWeight: FontWeight.w500,
    letterSpacing: -2.4,
    height: 0.98,
    color: color ?? textHi,
  ),
);
TextStyle kDisplay({Color? color}) => _appFontStyle(
  TextStyle(
    fontSize: 38,
    fontWeight: FontWeight.w600,
    letterSpacing: -1.2,
    height: 1.02,
    color: color ?? textHi,
  ),
);
TextStyle kTitle({Color? color}) => _appFontStyle(
  TextStyle(
    fontSize: 23,
    fontWeight: FontWeight.w600,
    letterSpacing: -0.6,
    color: color ?? textHi,
  ),
);
TextStyle kSection({Color? color}) => _appFontStyle(
  TextStyle(
    fontSize: 11.5,
    fontWeight: FontWeight.w600,
    letterSpacing: 1.8,
    color: color ?? muted,
  ),
);
TextStyle kBody({Color? color}) => _appFontStyle(
  TextStyle(
    fontSize: 15,
    fontWeight: FontWeight.w400,
    height: 1.55,
    color: color ?? muted,
  ),
);

ThemeData buildTheme(Palette p) {
  final base = ThemeData(brightness: p.brightness, useMaterial3: true);
  final family = activeFontFamily;
  final text =
      (ThemeController.instance.font.value == LumenFont.lumen
              ? GoogleFonts.spaceGroteskTextTheme(base.textTheme)
              : base.textTheme.apply(fontFamily: family))
          .apply(bodyColor: p.textHi, displayColor: p.textHi);
  final raised = Color.alphaBlend(
    Colors.white.withValues(
      alpha: p.brightness == Brightness.dark ? .045 : .42,
    ),
    p.surfaceHi,
  );
  final componentShape = RoundedRectangleBorder(
    borderRadius: BorderRadius.circular(lumenRadiusMd),
    side: BorderSide(color: p.line),
  );
  return base.copyWith(
    scaffoldBackgroundColor: p.bg,
    colorScheme: base.colorScheme.copyWith(
      primary: p.accent,
      onPrimary: foregroundFor(p.accent),
      secondary: p.accent,
      onSecondary: foregroundFor(p.accent),
      surface: p.surface,
      surfaceContainerLow: p.surface,
      surfaceContainer: raised,
      surfaceContainerHighest: p.surfaceHi,
      outline: p.line,
      outlineVariant: p.line,
      brightness: p.brightness,
    ),
    textTheme: text,
    appBarTheme: AppBarTheme(
      backgroundColor: Colors.transparent,
      elevation: 0,
      scrolledUnderElevation: 0,
      titleTextStyle: _appFontStyle(
        TextStyle(
          fontSize: 22,
          fontWeight: FontWeight.w600,
          color: p.textHi,
          letterSpacing: -0.5,
        ),
      ),
    ),
    iconTheme: IconThemeData(color: p.textHi),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: p.surfaceHi.withValues(alpha: 0.7),
      hintStyle: TextStyle(color: p.subtle),
      labelStyle: TextStyle(color: p.muted),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: BorderSide.none,
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: BorderSide(color: p.line),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: BorderSide(color: p.accentInk),
      ),
    ),
    dividerTheme: DividerThemeData(color: p.line, thickness: 1),
    progressIndicatorTheme: ProgressIndicatorThemeData(color: p.accentInk),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(foregroundColor: p.accentInk),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: p.accent,
        foregroundColor: foregroundFor(p.accent),
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(lumenRadiusMd),
        ),
        textStyle: const TextStyle(fontWeight: FontWeight.w800),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: p.textHi,
        side: BorderSide(color: p.line),
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(lumenRadiusMd),
        ),
      ),
    ),
    cardTheme: CardThemeData(
      color: raised,
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: componentShape,
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: p.surface,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(lumenRadiusLg),
        side: BorderSide(color: p.line),
      ),
      titleTextStyle: text.titleLarge?.copyWith(fontWeight: FontWeight.w800),
      contentTextStyle: text.bodyMedium?.copyWith(color: p.muted, height: 1.45),
    ),
    popupMenuTheme: PopupMenuThemeData(
      color: p.surface,
      surfaceTintColor: Colors.transparent,
      elevation: 12,
      shape: componentShape,
      textStyle: text.bodyMedium?.copyWith(color: p.textHi),
    ),
    snackBarTheme: SnackBarThemeData(
      backgroundColor: raised,
      contentTextStyle: text.bodyMedium?.copyWith(color: p.textHi),
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(lumenRadiusMd),
        side: BorderSide(color: p.line),
      ),
    ),
    tooltipTheme: TooltipThemeData(
      decoration: BoxDecoration(
        color: p.brightness == Brightness.dark
            ? const Color(0xF21A1E20)
            : const Color(0xF2FFFFFF),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: p.line),
      ),
      textStyle: TextStyle(
        color: p.textHi,
        fontSize: 11.5,
        fontWeight: FontWeight.w700,
      ),
    ),
    focusColor: p.accent.withValues(alpha: 0.30),
    hoverColor: p.accent.withValues(alpha: 0.12),
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
  static const _fontKey = 'lumen_font';

  final ValueNotifier<ThemeMode> mode = ValueNotifier(ThemeMode.dark);
  final ValueNotifier<Color> accent = ValueNotifier(defaultAccent);
  final ValueNotifier<LumenFont> font = ValueNotifier(LumenFont.lumen);

  /// Rebuild signal for appearance changes.
  Listenable get listenable => Listenable.merge([mode, accent, font]);

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
    final savedFont = p.getString(_fontKey);
    if (savedFont != null) {
      font.value = LumenFont.values.firstWhere(
        (option) => option.name == savedFont,
        orElse: () => LumenFont.lumen,
      );
    }
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

  Future<void> setFont(LumenFont value) async {
    font.value = value;
    final p = await SharedPreferences.getInstance();
    await p.setString(_fontKey, value.name);
  }
}

/// Resolves the active palette for the current mode + platform brightness,
/// assigns the global `activePalette`, and keeps both Android system bars
/// readable while the app draws edge-to-edge.
Palette resolvePalette(ThemeMode mode, Brightness platform) {
  final wantDark = switch (mode) {
    ThemeMode.dark => true,
    ThemeMode.light => false,
    ThemeMode.system => platform == Brightness.dark,
  };
  final a = ThemeController.instance.accent.value;
  final p = wantDark ? darkPaletteFor(a) : lightPaletteFor(a);
  activePalette = p;
  SystemChrome.setSystemUIOverlayStyle(
    SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: wantDark ? Brightness.light : Brightness.dark,
      statusBarBrightness: wantDark ? Brightness.dark : Brightness.light,
      systemNavigationBarColor: Colors.transparent,
      systemNavigationBarDividerColor: Colors.transparent,
      systemNavigationBarIconBrightness: wantDark
          ? Brightness.light
          : Brightness.dark,
      systemNavigationBarContrastEnforced: false,
    ),
  );
  return p;
}
