# Lumen Android TV D-pad navigation audit — source report

## Scope

- Audit the current `main` branch across the shell rail, command bar, Home, Search, Movies, Series, Live TV, My List, Downloads, Profile, detail pages, dialogs, login, and player.
- Verify complete operation using only D-pad Up/Down/Left/Right, Select, and Back.
- Verify focus visibility, deterministic directional movement, automatic scrolling, text entry, and recovery after navigation.
- Exercise both the offline demo and an authorized live provider account on an Android TV emulator.

## Authoritative requirements

1. Android TV requires every visible control to be reachable with the D-pad; focused lists must scroll, Select must activate, and navigation must remain predictable with an actionable focused item at all times.
   - https://developer.android.com/training/tv/get-started/navigation
2. A TV app must be fully usable with Up, Down, Left, Right, Select, Back, and Home, including controller key variants.
   - https://developer.android.com/training/tv/get-started/controllers
3. TV focus must be visibly differentiated and should use logical focus groups.
   - https://developer.android.com/design/ui/tv/guides/styles/focus-system
4. Flutter key events start at the primary focus and bubble through focus ancestors until handled; persistent owned FocusNodes and real text input/IME integration are required.
   - https://docs.flutter.dev/ui/interactivity/focus
5. Flutter supports grouping traversal regions and programmatically keeping newly focused controls visible.
   - https://api.flutter.dev/flutter/widgets/FocusTraversalGroup-class.html
   - https://api.flutter.dev/flutter/widgets/Scrollable/ensureVisible.html

## Evidence log

- Current baseline: local `main` contains three unpushed TV-specific commits on top of `github/main`.
- Android TV emulator: 1920x1080 physical display, 320 dpi, landscape app surface.
- Focus logging is enabled in the debug build through `LUMEN_LOG_FOCUS=true`.
- A real provider catalog and real live/VOD streams were exercised without storing its credentials in source, logs, screenshots, or this report.
- The initial route lands on the Home dock and Right enters `Home watch now`; Up reaches the shared command bar and Left returns to the current rail destination.
- Movies, Series, and Live categories traverse vertically beyond one viewport, scroll automatically, enter their grids with Right, move across rows in all four directions, and return to categories/rail with Left.
- A real five-season series traverses Back, Play next, My list, season tabs, every episode Play action, and every episode Download action in both directions.
- Search opens and reopens the TV keyboard with Select; section filters, category selection, results, and rail-return routes are reachable.
- Profile traverses Add account, all appearance and accent controls, Home customization, insights, downloads, refresh, history, diagnostics, legal, update (when present), and sign-out. Diagnostics, Legal, clear-history, sign-out, and exit dialogs were opened and dismissed with the remote.
- Empty Downloads traverses Rail → Open downloads folder → Command bar → Rail. Populated Downloads and My List are covered by widget route tests.
- The native player was exercised with a real live channel and VOD item. The remote traverses previous/play-pause/next, Back, captions, playback position, and other chrome without controls disappearing while focused. Channel switching preserves the active control focus.
- External keyboard Space toggles play/pause, J/L seek backward/forward, and S stops playback; D-pad arrows continue to navigate visible TV controls.
- The complete Flutter suite passes: 128 tests. Static analysis reports only 30 pre-existing informational style lints and no warnings or errors.

## Gap matrix

| Area | Requirement | Evidence/status | Intended remedy |
|---|---|---|---|
| Shell rail | Every destination reachable and Right enters page | Passed on emulator and in route tests | Stable per-page entry nodes and explicit return-to-rail routes |
| Command bar | Up/Left/Right transitions deterministic | Passed on Home and secondary pages | Deferred focus now schedules a Flutter frame before handoff |
| Categories | Up/Down scrolls full list; Right enters grid | Passed with real Movies, Series, and Live catalogs | Explicit category/grid boundary routing plus scroll-to-focus |
| Catalog grid | Four-way traversal and lazy scrolling | Passed across multiple rows and catalog pages | Deterministic post-frame retries keep lazy children reachable |
| Details | Buttons, seasons, episodes fully reachable | Passed on a real five-season series and route tests | Parent-owned episode action nodes and explicit row/column routes |
| Profile/settings | Every card, selector, action, dialog reachable | Passed through the complete settings graph | Explicit vertical chain and safe left-edge rail exit |
| Text input | Remote Select opens usable keyboard | Passed on provider login and Search | Persistent field nodes plus the custom D-pad keyboard |
| Player | All controls reachable; arrows/Select/Back work | Passed with real live and VOD playback | Arrow interception is limited to the video surface; focused controls remain visible |
| Lifecycle | Focus remains valid after loading/navigation | Passed across catalog loads, channel changes, dialogs, and route returns | Preserve active nodes and restore semantic entry focus after updates |

## Claim–source ledger

| Claim | Source | Use |
|---|---|---|
| All visible TV controls must be D-pad reachable and scrolling containers must scroll with focus | Android TV navigation guide | Acceptance criteria |
| Core TV interaction must work with only directional keys, Select, Back, and Home | Android TV controllers guide | Test matrix |
| Focus must be obvious and logically grouped | Android TV focus-system guide | Visual/focus-group review |
| Focused key events bubble through ancestors | Flutter focus guide | Diagnose competing handlers |
| Focus groups establish traversal regions | Flutter FocusTraversalGroup API | Architecture |
| ensureVisible can reveal newly focused descendants | Flutter Scrollable API | Off-screen focus correction |

## Conclusions

The audited build satisfies the Android TV remote-navigation acceptance criteria across the shell, content catalogs, detail pages, settings, dialogs, text input, and native player. Two root causes were corrected during live testing: the player consumed Left/Right before visible controls could traverse, and a deferred command-bar-to-rail handoff waited for an unscheduled frame. Explicit routes, persistent parent-owned nodes, scheduled focus handoffs, scroll-to-focus, and focus-preserving player chrome now remove those dead ends. The build is ready for signed-bundle verification and a closed-testing rollout.
