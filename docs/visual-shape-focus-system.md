# Lumen shape and focus design system

Status: implemented and verified in September 2026.

## Executive decision

Lumen uses one persisted, app-wide shape preference and one persisted,
app-wide focus preference. Both are available from **Profile → Make Lumen
yours** and update immediately on phone, tablet, desktop, and TV.

The system deliberately does not force every object to have the same radius.
Instead, it preserves a small visual hierarchy and scales each authored radius
proportionally. A compact button therefore remains tighter than a large sheet,
while both visibly belong to the same selected style. True circles, progress
tracks, and semantic pills remain circles or pills.

## Research findings

1. Flutter's theme system is designed to centralize component styling.
   `ThemeData` exposes component themes for buttons, inputs, cards, dialogs,
   menus, navigation, and other Material controls.[^1] Button style properties
   can resolve differently for focused, hovered, pressed, and disabled widget
   states.[^2]
2. Input geometry belongs in `InputDecorationTheme`. Flutter explicitly
   supports a state-aware input border, so focused fields can share the same
   radius and focus thickness as the rest of the app.[^3]
3. TV focus cannot rely on a color change alone. Android TV's official design
   guidance treats focus as a primary state and recommends combinations of
   scale, outline, glow, and color. Its reference scale values include 1.025,
   1.05, and 1.1 depending on element size.[^4]
4. Focus scaling requires spacing discipline. Android TV guidance warns that
   layouts must account for focused elements growing so adjacent content does
   not collide.[^5] Lumen therefore caps its strongest scale at 1.04 and keeps
   compact grid spacing around focusable programme cells.
5. A visible outline is the safest baseline for keyboard accessibility. WCAG
   2.2's Focus Appearance guidance describes a solid two-pixel outline as a
   straightforward way to satisfy the minimum focus area, and W3C technique
   G195 recommends an author-supplied visible focus indicator.[^6][^7]

## User-facing presets

### Corner style

| Setting | Scale | Intended feel |
|---|---:|---|
| Crisp | 0.58× | Precise, compact, desktop-like |
| Balanced | 1.00× | Lumen default |
| Soft | 1.42× | Friendlier and more rounded |

Authored radii between 3 and 90 logical pixels are scaled and constrained to a
safe range of 3.5–48. Values at or below 3 remain unchanged because they are
usually progress tracks or tiny indicators. Values at or above 90 remain
unchanged because they intentionally describe pills. `BoxShape.circle`,
`CircleBorder`, and `ClipOval` remain circular.

### Focus style

| Setting | Scale | Outline | Glow | Best fit |
|---|---:|---:|---:|---|
| Outline | 1.000× | 2 px | None | Calm desktop/keyboard use |
| Lift | 1.025× | 2 px | 8 px | Default cross-device mode |
| Glow | 1.040× | 2.5 px | 14 px | Strong ten-foot TV visibility |

All modes retain at least a two-pixel accent outline. The accent is already
contrast-corrected by Lumen's palette system, so changing the accent also
updates the focus signal without introducing a second unrelated focus color.

## Implementation architecture

- `ThemeController` owns `corners` and `focus` value notifiers and persists
  them as `lumen_corner_style` and `lumen_focus_style`.
- `lumenCorner(base)` is the single geometry resolver used by authored UI
  surfaces, including the Lumen mark and wordmark lockups.
- `buildTheme` applies the selected shape to Material inputs, text buttons,
  filled buttons, outlined buttons, icon buttons, cards, dialogs, popup menus,
  snackbars, and tooltips.
- `RemoteTap` and `FocusableTap` apply the selected outline, scale, and glow to
  custom controls used throughout TV and keyboard interfaces.
- Dense custom focus surfaces in Search, EPG, subtitle search, and the custom
  accent editor use the same focus tokens instead of independent constants.
- The app root already rebuilds from `ThemeController.listenable`; shape and
  focus changes therefore apply immediately and do not require a restart.

## Repository audit and migration

The pre-implementation audit found 211 authored shape declarations across 19
UI files and 60 focus-related occurrences. The migration routes every authored
`BorderRadius.circular`/`Radius.circular` value through the shared resolver.
Special constructors (`BorderRadius.vertical` and
`BorderRadius.horizontal`) were migrated as well.

The audit treats the following as intentional exemptions:

- circular avatars, loading indicators, round playback actions, and radio
  controls;
- progress tracks and indicator lines with 2–3 px radii;
- explicit pill values of 99 or 999;
- artwork aspect ratios and clipping that carry content meaning rather than
  control styling.

This distinction prevents customization from turning avatars into rounded
squares or pills into ordinary rectangles.

## Verification contract

The automated coverage verifies:

- compact Profile remains scrollable and overflow-free;
- the TV Profile D-pad graph reaches every appearance, font, corner, focus,
  accent, playback, privacy, and account action;
- corner and focus preferences persist to local settings;
- the selected focus mode changes the real remote wrapper's scale, outline,
  radius, and glow;
- the standard full test suite remains green under the default preset;
- static analysis and an Android debug build continue to succeed.

For future components, use `lumenCorner()` for authored rounded geometry,
prefer Material component themes where available, and use `RemoteTap` or
`FocusableTap` for custom interactive surfaces. New hard-coded focus widths,
scales, or glows should be treated as regressions.

## Sources

[^1]: Flutter, [ThemeData class](https://api.flutter.dev/flutter/material/ThemeData-class.html).
[^2]: Flutter, [FilledButton.styleFrom](https://api.flutter.dev/flutter/material/FilledButton/styleFrom.html) and [FilledButton class](https://api.flutter.dev/flutter/material/FilledButton-class.html).
[^3]: Flutter, [InputDecorationThemeData.border](https://api.flutter.dev/flutter/material/InputDecorationThemeData/border.html).
[^4]: Android Developers, [Focus system on TV](https://developer.android.com/design/ui/tv/guides/styles/focus-system).
[^5]: Android Developers, [Layouts for TV](https://developer.android.com/design/ui/tv/guides/styles/layouts).
[^6]: W3C, [Understanding Success Criterion 2.4.13: Focus Appearance](https://www.w3.org/WAI/WCAG22/Understanding/focus-appearance.html).
[^7]: W3C, [G195: Using an author-supplied, highly visible focus indicator](https://www.w3.org/WAI/WCAG22/Techniques/general/G195).
