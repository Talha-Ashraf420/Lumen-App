# EliteStocksOne optimization review

Reviewed on 2026-09-30 against Lumen `a67d760` and EliteStocksOne
`011bd22c0f333f48851f67349a05573d66071454` (159 additional commits, 42 changed
files). The remote head was fetched before review. Conclusions refer to that
snapshot, not to future changes in the other repository.

Source: [complete comparison](https://github.com/anuragrajpandey/EliteStocksOne/compare/a67d760...011bd22).
Reviewed the accumulated changes and relevant callers/tests, rather than
assuming each commit title describes a verified fix. The fork's build scripts
and application were not executed.

## Adopted

| Change | Benefit | Lumen integration |
| --- | --- | --- |
| Catalog batches of 300 rows | Bounds the temporary SQL operation buffer and synchronous JSON serialization per event-loop turn | Keeps all chunks inside the original transaction; generation rejection, ordering, and rollback remain intact |
| EPG channel/programme batches of 300 | Bounds import operation buffers and yields between chunks | Keeps the existing staged-generation publication model; incomplete guides remain hidden |
| Retain the client when saved services are unchanged | Avoids closing a client and clearing its requests immediately after Home starts loading | Compares URL, username, password, playlist URL, demo state and service order; does not wait for slow profile hydration |
| Pause hero rotation outside the viewport | Avoids advancing images and starting new metadata lookups when the hero is scrolled out of view | Also respects inactive tabs, background lifecycle, covering routes and full-screen playback |
| Avoid flattening combined search inputs into a temporary list | Removes one full list of references before filtering | Uses lazy expansion and retains all matches and existing sort/pagination behavior |

Batching reduces peak operation-buffer allocation, not the size of the provider
response itself. The catalog transaction still locks database operations until
the replacement finishes; yielding lets Dart process events but is not a
guarantee of a frame-time target. No device FPS or percentage speedup is claimed.

## Changes deliberately not imported

| Area | Finding |
| --- | --- |
| Cold search | Searches only the first six categories and uses 900 ms item timeouts. Valid titles in later categories or on slower providers disappear. `Future.timeout` stops waiting but does not cancel the underlying work. |
| Cached search refresh | The claimed full-import avoidance still falls through to `vodStreams(client, null)` / equivalent calls. That can fetch the whole provider anyway. |
| Combined search cap | Stops at the first 500 matches before sorting. This can omit the best/newest results from later sources and truncate pagination. |
| Search sequencing | Later media types start from `_storePage`. A failure before storing a page can leave subsequent sections unstarted. |
| Waiting for profile hydration | Makes successful login wait for all storage/download initialization without a bound. Conflicts with Lumen's existing regression test that Home opens while hydration is pending. |
| Removing cached `*` lists | Worth reconsidering with a separate paged refresh API. Current page reads call whole-list methods for revalidation; deleting their memoized futures alone can rehydrate the same large list and add refresh work. |
| Native playlist cap | Limits the Android playlist to 100 neighbours on either side without refilling it. Reduces marshaling, but next/previous/channel browsing loses the remaining channels. Needs a sliding window protocol first. |
| Media3 on every Android phone | Changes playback behavior and bypasses the Flutter player. Requires device tests for PiP, split view, subtitles, downloads and focus; a successful APK build cannot establish equivalence. |
| Player open/play/dispose serialization | Sensible direction, but the new queues await previous opens without a bound, and stop/dispose handling does not clearly cover all play/pause work. Needs a per-player lifecycle design and failure/reopen tests. |
| Automatically marking completed titles watched | Useful feature, but completion events also need testing during source changes/errors before changing the user's watch history. |
| Theme/focus simplification | Reduces rebuild sources by removing appearance options and focus outlines. This sacrifices Lumen customization and TV focus visibility. |
| Mobile Home redesign | Ten shelf futures are created eagerly, additional categories are loaded, and missing-artwork enrichment is awaited before showing a shelf. This is not automatically a startup optimization. |
| TMDB discovery/enrichment | Adds India-specific discovery and matching. Missing artwork beyond the lookup allowance is omitted; static discovery caches have no expiry. Treat as a separate product feature with coverage/privacy/locale requirements. |
| Native decoder prewarming | Disabling Android prewarm is tied to making Media3 primary. Needs startup/first-play measurements before changing Lumen's phone engine behavior. |
| Branding, navigation, player controls and packaging | Mostly product/rebrand changes, not demonstrated performance improvements. The Android signing workflow creates a new keystore for each run and is unsuitable for stable upgrades. |

Reference: [Dart Future.timeout contract](https://api.dart.dev/dart-async/Future/timeout.html).

## Attribution

The database batching is adapted from Anurag Raj Pandey's commits
[`25c7d44`](https://github.com/anuragrajpandey/EliteStocksOne/commit/25c7d44),
[`1347193`](https://github.com/anuragrajpandey/EliteStocksOne/commit/1347193), and
[`4756c59`](https://github.com/anuragrajpandey/EliteStocksOne/commit/4756c59).
The unchanged-service guard and viewport check are adapted from the same
repository's accumulated `main.dart` and `home_screen.dart` changes. Combined
search uses the allocation concern raised in `06b29a6` while preserving full
results. The source repository distributes these under MIT, with the same
Talha Ashraf copyright notice retained in Lumen's root LICENSE. No rebranding,
signing, credentials, external links or workflow changes were imported.

## Verification

- Complete local Flutter suite: **255 tests passed**.
- Static analysis: no errors or warnings; 21 informational notices remain
  with the installed Flutter SDK. `git diff --check` passes.
- New serialization tests observe at most 300 row reads per event-loop turn
  while importing 1,805 catalog items and 905 EPG channels/programmes.
- Catalog tests verify pagination across chunk boundaries, provider order,
  stale-generation rejection and rollback after a failure at item 650.
- EPG tests verify staged chunks remain invisible until import completion.
- Session test verifies unchanged service reload preserves client and Home state;
  existing delayed/failed hydration tests still pass.
- Home widget test verifies carousel advancement pauses after scrolling out of
  view and resumes when visible.
- Physical Android TV soak/fast-scroll testing is still required. This review
  does not establish that every reported TV freeze has been reproduced or fixed.

## Next optimization work

1. Profile large real catalogs on the affected TV: Dart heap, image cache,
   database read latency, frame times and queued provider requests.
2. Separate paged revalidation from APIs that return a whole list; then bound
   retained category data with an eviction policy that preserves active work.
3. Add a refillable native playlist window, preserving global channel navigation.
4. Test player command ordering with stalled opens, rapid channel changes and
   stop/reopen before adopting any playback-engine changes.
