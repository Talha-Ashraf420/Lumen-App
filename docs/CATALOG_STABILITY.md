# Catalog memory and TV browsing stability

## Changes

- Specific-category Movie, Series and Live grids read 48-item SQLite pages.
  Background revalidation no longer reads the same category back as a
  100,000-item list. A shared refresh indexes the provider response, then drops
  the completed refresh job. The current grid remains visible.
- Successful indexed categories have a five-minute refresh cooldown. Empty or
  failed background refreshes have a short backoff; explicit cache refresh
  clears it. Pagination does not issue one provider request per page.
- Browse requests have a lifetime. Category, query, sort and section changes,
  refresh and disposal cancel obsolete queued page work. A shared request
  continues if another reader still needs it. Running HTTP calls are not
  forcibly aborted: their obsolete results are discarded without closing the
  shared playback client.
- Account changes cancel the previous scheduler's pending queue. Epoch guards
  prevent late responses, retries, artwork and all-category import
  continuations from publishing stale state or reclaiming the current client.
- Settled full-list caches retain at most four buckets and 2,000 items per
  media kind. Larger responses still reach their caller without becoming a
  permanent cache entry. In-flight requests stay shared. Detail caches are
  bounded separately (24 movies, eight series).
- Each SearchScreen keeps six recently visited category/section pages. Inactive
  pages retain at most 96 items and reload subsequent pages from the index.
  The current page and its focus position are not truncated. Merged categories
  now append pages rather than mounting their entire combined grid at once.
- Optional logo enrichment shares the bounded network scheduler instead of
  launching an independent burst of requests. No new pop-ups or tile spinners.

## Verification

`flutter test --no-pub` and `flutter analyze --no-pub --no-fatal-infos`.

Regression coverage includes:

- A 10,000-item category: 49 database rows per 48-item page, one shared refresh,
  no retained full Movie list after indexing, and no refetch for the next page.
- Three blocked provider requests plus 20 queued page requests: cancellation
  removes the queued work without waiting for the three active calls.
- A shared reader surviving another reader's cancellation; token listeners
  continuing to work after one of several jobs completes.
- Switching to Demo with old requests/imports pending, without old writes or
  account ownership being restored by a late continuation.
- Indexed Live/Series pagination and bounded settled legacy caches.
- TV navigation through 14 categories plus rapid remote repeats, bounded
  retained grids, and an attached content focus target afterwards.
- Complete pagination of merged categories; existing post-refresh focus,
  return-to-category, offline recovery and session transition tests.

These counters measure logical retained items and queued work, not total heap
bytes or physical-device frame times. No real three-hour playback soak or
low-memory Android TV profiling is claimed by the automated tests.

## Remaining boundaries / device validation

Xtream category endpoints still deliver whole JSON responses. This change
limits retention after indexing, not the peak size of an individual provider
response. Whole-library fallback imports and merged-category sorting still
temporarily aggregate full lists; they are not yet fully SQL-paged end-to-end.
The actively browsed grid can grow as the user loads more pages so its scroll
and focus position remain stable. It is trimmed after leaving the category.

Before release, run on a low-memory TV: play Live for at least three hours,
return, repeat fast Up/Down through categories, switch Movies/Series/Live and
then Demo. Confirm visible data, stable focus and playable favorites; collect
heap, frame and network traces. Exercise an unavailable provider too. Do not
label the intermittent original freeze conclusively reproduced/fixed solely
from these regression tests.
