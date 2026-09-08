# Live playback benchmark — 8 September 2026

This report uses one authorized HD channel from the same provider account for
every run. The endpoint, account details and stream identifier are deliberately
redacted. VLC and mpv were measured on the development Mac; Media3 was measured
in the local 1080p Android TV emulator on the same network. A final physical-TV
soak test is still required before production rollout.

## Source behaviour

- The account advertised MPEG-TS (`.ts`) as its only allowed output format.
- The equivalent `.m3u8` request returned HTTP 405, so this account cannot be
  used for a genuine HLS-versus-TS playback comparison.
- Three direct TS downloads had 0.738–0.787 second time-to-first-byte and
  transferred at 1.52–3.37 MB/s (about 12.1–26.9 Mbit/s).
- Each successful live response ended after only 3.34–4.34 seconds and contained
  5.1–12.4 MB. The available throughput was high; repeated response EOFs were
  the actual interruption.

## Player results

| Player/configuration | Startup | Observed buffer | Result |
|---|---:|---:|---|
| VLC 3.0.23, 3 s network cache | ~3 s | VLC demux rate ~3.7–3.9 Mbit/s | Decoded without loss, then stopped when the finite HTTP response ended. `--http-reconnect` did not join the next response. |
| Lumen mpv baseline | 3.17 s | Average 1.16 s; maximum 2.68 s | The response ended after 6.2 s. mpv reported premature HTTP EOF and a damaged final H.264 packet. |
| Lumen mpv with FFmpeg stream reconnect | 3.16 s | Average 11.84 s; maximum 16.36 s | Two provider EOFs were reconnected immediately during the 20 s run. Zero rebuffer events. MPEG-TS discontinuity warnings were recoverable. |
| Media3 baseline | 1.95–3.2 s per response | Maximum 7.7–9.3 s | Each EOF produced `STATE_ENDED`, discarded the buffer and caused a visible ~3 s reopen gap. |
| Media3 with Lumen EOF joiner | 2.26 s | Continued loading across responses | Five finite HTTP responses were joined during a >2 minute run. After the initial `BUFFERING → READY`, there was no later buffering or ended state, and video was still rendering at the end. |

## Implemented policy

- mpv now applies FFmpeg reconnect options through `stream-lavf-o`. Using
  `demuxer-lavf-o` does not reach the HTTP transport and did not solve the EOF.
- Media3 wraps raw live TS HTTP reads and reopens the same endpoint before EOF
  reaches the extractor. HLS playlists and HLS media segments retain normal EOF
  behaviour.
- Lumen tries the provider-supplied format first, then the alternate HLS/TS
  source. This avoids a guaranteed HLS failure for TS-only accounts.
- Android TV keeps Media3 as its preferred native-SurfaceView engine. If its
  bounded recovery is exhausted, Lumen automatically returns to the bundled
  mpv engine.
- Users can choose **Balanced** (default), **Stable**, or **Low latency** under
  Profile → Library & playback. The setting is shared by both playback engines.

## Remaining validation

- Run a 30–60 minute soak test on the target physical Google TV in Balanced and
  Stable modes.
- Repeat the HLS comparison with an authorized account that actually advertises
  `.m3u8` output.
- Test several codec combinations (H.264/AAC, HEVC/AAC, interlaced broadcast)
  because source closure and decoder compatibility are independent problems.
