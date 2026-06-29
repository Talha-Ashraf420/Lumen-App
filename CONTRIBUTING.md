# Contributing to Lumen

Thanks for your interest in improving Lumen! 🎉 This is a friendly project and
all contributions — code, docs, bug reports, ideas — are welcome.

## Quick start

```bash
# Prerequisites: Flutter 3.38.x (Dart 3.10+). Check with: flutter doctor
git clone https://github.com/Talha-Ashraf420/Lumen-App.git
cd Lumen-App
flutter pub get
flutter run            # pick a device, or:
flutter run -d macos   # / -d chrome / -d <android-device>
```

To test playback you'll need your own IPTV source (Xtream codes or an M3U URL) —
Lumen ships with no content. Free public M3U lists (e.g. iptv-org) work for
testing Live TV.

## Project layout

```
lib/
  main.dart            App entry, theme, login gate
  xtream.dart          Data source: Xtream API + plain M3U/XMLTV mode
  playback.dart        PlaybackController (single libmpv surface)
  downloads.dart       Offline download queue (pause/resume)
  updater.dart         In-app update check/install
  theme.dart           Accent-derived palette + ThemeController
  screens/             UI screens (home, guide, player_host, search, ...)
  widgets.dart         Shared widgets (cards, glass, wordmark, FocusableTap)
.github/workflows/     CI: builds all 6 platforms + publishes releases
docs/                  Architecture notes, blog, screenshots
```

The "how it works" write-up in [`docs/blog/building-lumen.md`](docs/blog/building-lumen.md)
is a good architectural primer.

## Conventions

- **Format & analyze before pushing:** `dart format .` and `flutter analyze`
  (CI and reviewers expect **0 analyzer errors**).
- Dart imports use **relative paths** (`import '../theme.dart'`).
- Use the theme-aware colour getters (`accent`, `surface`, `textHi`, …) — never
  hard-code brand colours, so custom accents keep working.
- Keep widgets `const` where they don't read theme getters that must update live.
- Match the surrounding style; keep PRs focused (one thing per PR).

## Submitting a change

1. **Find or open an issue** — look for [`good first issue`](https://github.com/Talha-Ashraf420/Lumen-App/labels/good%20first%20issue)
   and [`help wanted`](https://github.com/Talha-Ashraf420/Lumen-App/labels/help%20wanted). Comment to claim it.
2. Fork → branch (`feat/...` or `fix/...`).
3. Make the change; run `flutter analyze` (0 errors) and test on at least one platform.
4. Open a PR describing **what** and **why**, with a screenshot/GIF for UI changes.

## Good areas to help

- **Cast to TV** (Chromecast / DLNA) — the big open feature.
- New language translations / localization.
- Per-platform polish (Windows/Linux), accessibility, keyboard/remote shortcuts.
- Bug fixes from the issue tracker.

By contributing you agree your work is licensed under the project's [MIT License](LICENSE).
