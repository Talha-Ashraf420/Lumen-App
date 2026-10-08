# Lumen UI refresh

## Direction

Make browsing feel like a personal cinema: artwork first, readable type,
one clear selected destination, and calm controls over video. Keep the existing
Home, Movies, Series, Live, Search destinations and saved customization.

## Research and decisions

- [Apple tab bars](https://developer.apple.com/design/human-interface-guidelines/tab-bars):
  keep navigation predictable. Retain labels and stable positions; selection
  follows the displayed page, independently of keyboard focus.
- [Material typography](https://m3.material.io/styles/typography/applying-type):
  use a small hierarchy of type roles. Lumen uses bundled Space Grotesk;
  Inter and Device are distinct whole-app alternatives, with full-sentence
  previews. Body text stays regular and headings use restrained medium weights.
- [Material motion](https://m3.material.io/styles/motion/overview):
  use motion to explain a state change. A single moving tab indicator is more
  useful than several unrelated bouncing items. Respect Reduce Motion and
  avoid animating retained catalog pages or expensive video surfaces.
- [Infuse playback controls](https://support.firecore.com/hc/en-us/articles/215090987-Playback-Controls):
  keep transport and playback options distinct. Expose play/pause, seek,
  subtitles, and channel selection directly; place secondary settings together.
  Gestures supplement visible controls.

These are interaction references, not pixel-for-pixel copies of another app.

## First implementation

1. Phone navigation: a compact elevated dock, one sliding icon indicator,
   outlined/filled icon states, readable permanent labels, 48px minimum targets,
   distinct keyboard focus, and correct RTL/reduced-motion behavior.
2. Type and layout: shared page/section/body styles, calmer section headings,
   stronger phone hero title, consistent catalog headings and local font assets.
3. Flutter player (iPhone, desktop and compatibility playback): reduce chrome,
   remove redundant controls, enlarge transport targets, expose labeled phone
   actions, and make additional playback tools reachable in More. Keep TV
   transport placement and the existing auto-hide/recovery behavior.
4. Verify the navigation regression, compact and enlarged-text layouts,
   keyboard activation, RTL, reduced motion, font preferences, and player actions.
   Render representative demo-only screens before installing the local iPhone build.

## Follow-up passes

- Review the updated detail pages and focused Settings pages on physical devices.
- Bring the native Android TV Media3 controller into the same visual family,
  with a dedicated D-pad/device validation pass. Its controls are separate from
  Flutter's player; this pass does not claim to redesign that native controller.
- Refine the mini-player and landscape phone composition based on device testing.

## Constraints

Keep theme/accent/corner preferences, source labels, Home shelf customization,
catalog caching, playback engines and focus restoration. No new font network
requests, full-screen blur effects or repeated animations during fast browsing.
No public release is part of this design pass.

## First-pass result — 8 October 2026

Implemented the dock, shared type hierarchy, calmer section headings, responsive
Home actions, and mobile Flutter player controls. Playback options use a solid
panel rather than a blur over moving video. New tab/player transitions and the
Home rotation honor Reduce Motion. Existing Home shelves and personalization
remain unchanged. Phone search/category navigation regressions are covered.

Verification:

- Full Flutter suite: 288 passed; optional screenshot test skipped by default.
- Opt-in real-widget preview test: passed separately, with bundled demo artwork
  and fonts; reviewed Home, dark/light Live, and a player-control fixture.
- Covered 320px width, 1.5x text, RTL indicator alignment, keyboard activation,
  reduced motion, and user font choices.
- Fixed typography-related overflows in Home actions, catalog sort controls,
  series detail hero, and the EPG filter.
- Analyzer: no errors or warnings; 21 existing informational lints remain.
- Signed iOS release build succeeded and installed on the connected iPhone.
  On-device playback/gesture validation still requires a hands-on check; widget
  fixtures do not exercise a real decoder or stream.

No commit, push, or store release was performed. Native Android TV controller,
Profile/detail visual redesign, and mini-player refinement remain follow-ups.

## Settings and typography follow-up — 8 October 2026

Replaced the all-in-one Profile dashboard with a Settings menu and six routes:
Accounts & services, Viewing profiles, Appearance, Playback, Library & downloads,
and Help & about. Back returns to the originating menu row; session changes close
the settings route. Account status is fetched only on the Accounts page, not when
opening the menu or unrelated preferences. Existing settings remain available.

Font preferences now change the entire app: Lumen uses Space Grotesk, Inter uses
Inter, and Device uses the platform font. Preview sentences make the differences
visible. Reduced heavy weights across navigation, browsing, and detail screens.
Phone font, shape, and focus choices use readable full-width layouts.

Verification: 291 Flutter tests passed; the optional screenshot test is run
separately. Covered all six routes, menu focus restoration, D-pad navigation,
sign-out, and a 320px phone with 1.5x text. No commit, push, public release, or
installation of this follow-up has been performed.

## Border, menu, and avatar refinement — 9 October 2026

- Split the Settings menu into three groups below an active-viewer avatar,
  replacing its sparse single panel. Reserve bottom space only for the phone
  dock; wide layouts no longer inherit the phone's large bottom inset.
- Replace letter/number avatars in Home utilities, the command bar, service
  accounts, and the viewer picker with lightweight, deterministic local artwork.
  Viewer avatars are keyed by stable viewer ID, so renaming preserves them.
  There are no image requests, photo permissions, or new profile data to store.
- Make Crisp and Soft corners visibly different. Separate Outline (3px ring,
  no shadow), Lift (offset neutral shadow), and Glow (accent halo). A larger live
  preview explains keyboard/remote focus even on touch devices. Reduced-motion
  users retain the border/shadow distinction without scaling animations.
- Use neutral, quieter borders on shared glass surfaces, reserving the strong
  accent edge for focus and selection.

Verified phone menu grouping, avatar replacement, live focus preview updates,
320px enlarged-text appearance, and TV navigation using widget tests. These
changes require a new device build; the previous installed build predates them.

## Split-view browser — 9 October 2026

Redesigned the Flutter split browser with a consistent header and Close action,
breadcrumb Back navigation, local category/collection search, larger contained
logos, lighter typography, and clear add/current-stream states. Rows are lazy;
search filters only the loaded collection and does not fetch the full provider
catalog. Loading errors offer Retry, and generation checks discard responses
after navigating away. Channel titles inherit the selected app font.

The native Android TV player now uses a searchable, recycled channel list for
both starting split view and changing a split pane. It shows channel numbers,
My List markers, current-pane status, and a high-contrast remote selection.
It excludes the other pane's channel and restores player-control focus on close.
No extra streams or artwork requests are started by browsing the native list.

Validation covers filtering without provider calls, current-stream protection,
late category/channel responses, failed episode loading, and compact landscape
keyboard navigation. Native Android debug Kotlin compilation succeeds. Actual
two-decoder playback and native remote interaction still need device testing;
this change has not been installed or published.

## Consistent page spacing — 9 October 2026

Page-level content uses shared responsive gutters in `responsive.dart`: 24px on
phones, 20px below 360px width, and 32px on wide screens. Headers, search/filter
rows, grids, Home collections, Settings pages, library tools, guide tools, and
movie/series details use these edges. Full-bleed artwork/video and internal
button/card padding are intentionally separate from the page gutter.

Floating-dock destinations keep scroll clearance including the phone's bottom
safe area. Grid focus calculations use the actual padded content width. Shared
spacing tests cover 320/390/844/1280px widths and side/bottom safe areas. Home,
Live (light/dark), and Settings were rendered for visual review. No public
release, commit, or push is included in this spacing pass.

Validation: 301 tests passed (one optional preview skipped in the full suite;
preview passed separately). The small-screen guide toolbar uses compact
accessible Refresh/Now controls so larger gutters do not cause overflow.

## Player-panel phone corrections — 9 October 2026

Landscape player panels consume only the right/top/bottom safe area, not the
left notch inset at their internal edge. Their width reserves the right inset
in addition to usable content space. A separate modal barrier dismisses the
panel without entering the underlying playback gesture recognizers. Split
categories use one evenly divided tab row and a short, untruncated heading.

Transient playback status follows the measured header in normal layout; when
controls are hidden it uses its own safe-area lane. It is hidden behind open
panels. Shared custom and Material controls suppress navigation focus outlines
and focus scaling on installed phone/tablet apps, while retaining TV/desktop
focus, selected states, text editing, and accessibility semantics.

Regression coverage includes landscape notch insets, portrait sizing,
outside-tap dismissal without playback taps, header/status separation, and
phone versus TV focus. The real split browser is also rendered inside the
production panel with landscape iPhone safe insets for visual review.
