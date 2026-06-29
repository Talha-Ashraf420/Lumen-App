---
title: "Building Lumen: a cross-platform IPTV player with Flutter + libmpv"
published: false
tags: flutter, opensource, android, dart
canonical_url: https://github.com/Talha-Ashraf420/Lumen-App
---

# Building Lumen: one Flutter codebase, six platforms, real video

I pay for an IPTV subscription, but every player I tried looked like it was built
in 2014. So I built **[Lumen](https://github.com/Talha-Ashraf420/Lumen-App)** — a
free, open-source IPTV player that feels like a modern streaming app, from a single
Flutter codebase, running on **Android, Android TV, iOS, macOS, Windows and Linux**.

It's a *player* — you bring your own Xtream codes or M3U playlist; it ships with no
content. Here's how it came together and the parts that were genuinely hard.

## The stack
- **Flutter / Dart** for the UI on all six targets.
- **[media_kit](https://pub.dev/packages/media_kit)** (libmpv) for native playback —
  it eats MKV/TS/HLS without complaint, which generic players choke on.
- **Xtream Codes API** + a hand-rolled **M3U / XMLTV** parser for sources.
- **TMDB** for movie/series artwork, ratings, cast and trailers.

## The single-surface player problem
The biggest architectural decision was the video player. libmpv renders into **one**
texture; if you mount two `Video` widgets on one controller, it races and crashes on
desktop. But I wanted a player that survives navigation *and* a picture-in-picture
mini-player.

The fix: **one persistent player overlay** mounted above the app (a bare `Overlay` +
`Material`, not a second `Navigator`, so clicks pass through). The same single video
surface animates between full-screen and a docked mini — it's never recreated, so
playback is continuous and nothing races.

## Picture-in-Picture, honestly
- **Android**: real OS PiP via `onUserLeaveHint` + a method channel — the video keeps
  playing in a floating window when you background the app.
- **iOS/desktop**: system PiP needs AVKit, which libmpv can't feed. So those get the
  in-app mini-player instead. Knowing where a platform *won't* cooperate saved a lot
  of wasted effort.

## A real TV-guide grid
The EPG guide is a channels × time grid with a sticky channel column, a sticky time
axis, a red "now" line, and lazy per-channel EPG loading — all kept in sync with
`linked_scroll_controller`. The fun bug: some providers return overlapping/duplicate
programmes, so blocks stacked on top of each other. A sort-and-dedupe pass into a
clean non-overlapping sequence fixed it.

## Offline downloads with pause/resume
Downloads stream the provider's URL to a real folder, with a queue (most IPTV accounts
allow **one connection**, so parallel downloads make the server drop the first).
Pause keeps the partial file; resume continues with an HTTP `Range: bytes=N-` request
and falls back to a clean restart if the server ignores ranges. State persists across
restarts.

## Theming you can actually change
The whole palette is **derived from one accent colour** — surfaces are tinted toward
the accent's hue, in both light and dark — so picking a colour recolors the entire UI,
not just buttons. (Gotcha: `const` widgets like the logo wouldn't recolor because
Flutter skips rebuilding identical const instances — de-`const` them and they update.)

## Shipping to six platforms
A single GitHub Actions workflow builds **all six** targets and publishes them to a
rolling "latest" release. For Android I added a stable signing key + auto-incrementing
`versionCode`, so an **in-app updater** (and Obtainium) can install new builds cleanly
with no signature conflicts.

## Lessons
- Pick the hard dependency (libmpv) for the thing that matters (playback) and design
  the rest around its constraints (one surface).
- Be honest about platform limits (iOS PiP, macOS self-update) instead of fighting them.
- Real provider data is messy — defensive parsing (overlapping EPG, missing
  content-length, ignored range requests) is most of the work.

Code, downloads and screenshots: **https://github.com/Talha-Ashraf420/Lumen-App**.
Feedback and stars welcome.
