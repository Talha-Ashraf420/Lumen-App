# Lumen — Google Play submission sheet

This document is a release checklist, not a guarantee of approval. Google reviews the binary, listing, credentials, developer account, and all content reachable during review.

## Listing copy

- App name: `Lumen`
- Category: `Video Players & Editors`
- Short description: `A private media player for your authorized HTTPS playlists and services.`
- Suggested full description:

  > Lumen is a polished media player for services and playlists you already have the legal right to use. Connect an authorized HTTPS Xtream-compatible service or M3U playlist, browse your catalog, view a program guide, save favorites, resume playback, and manage offline copies where your content rights permit it.
  >
  > Lumen does not provide, sell, host, curate, or endorse any channels, subscriptions, playlists, streams, or media. You must supply your own authorized source. Lumen is not affiliated with any content provider.
  >
  > Features include phone, tablet, and Android TV layouts; picture-in-picture; favorites and continue watching; optional metadata and subtitle integrations; and encrypted local credential storage.

Do not use phrases such as “free TV,” “premium channels,” “watch anything,” provider/reseller brands, sports-league names, or claims that imply Lumen supplies content. Do not show unlicensed movie posters, channel logos, live sports, or premium-service brands in screenshots.

## Required actions before the first upload

- [x] Rotate the upload keystore. The former key was committed to Git history and is retired. The new upload key is outside Git with an owner-only local backup.
- [ ] Purge `android/app/lumen.keystore` and `android/key.properties` from all public Git history. This is still recommended because the retired credential remains visible in old commits, but history rewriting must not delay adoption of the new key and must never rewrite a key that has already been enrolled with Play.
- [x] Verify `https://lumen-launch.vercel.app/privacy` is public, active, non-geofenced, and readable without login.
- [ ] Create the app in Play Console with application ID `com.talhaashraf.lumen`. An application ID cannot be changed after publishing.
- [ ] Use Google Play App Signing. Upload an Android App Bundle (`.aab`), never the validation bundle signed with the compromised old key.
- [ ] Build the candidate with `tool/build_play_aab.sh`; it enforces the Play channel's HTTPS-only provider policy and refuses to build when signing credentials are missing or tracked by Git. Direct TV APKs remain compatible with user-authorized HTTP providers.
- [ ] Test the exact release bundle on a phone, tablet, and Android TV/Google TV device or emulator with D-pad navigation.
- [ ] If TMDB enrichment is enabled, supply the key at build time with `--dart-define=TMDB_API_KEY=...`, comply with TMDB's API terms, and keep the in-app attribution. The former embedded key must be treated as exposed.

## App access for review

Lumen requires an external source, so App access must contain complete reviewer instructions and a working, legal HTTPS demo source. Supply either:

- a dedicated Xtream-compatible reviewer account with server URL, username, and password; or
- a stable HTTPS M3U demo playlist and optional HTTPS EPG URL containing only media you own or are licensed to distribute.

The account must remain active throughout review, work from Google's review region, avoid OTP/2FA, and expose enough content to test playback, search, favorites, history, downloads, and TV navigation. Explain that Lumen supplies no content. Never submit credentials for an unauthorized IPTV reseller.

## Data Safety draft — verify against the final binary

Use the detailed, conservative answer sheet in
`docs/play-console-answers.md`. Re-check the form whenever an SDK, analytics
tool, crash reporter, ad service, API, or data flow changes.

## Play Console declarations

- Privacy policy: use the verified public URL above.
- Target audience: exclude children. Recommended starting selection: `18 and over` unless you have a documented reason for a broader audience.
- Content rating: answer the IARC questionnaire truthfully based on all content reachable through the reviewer source. A neutral demo source is not permission to understate app capabilities.
- Ads: `No`, while the binary contains no ad SDK or ad placements.
- App access: `All or some functionality is restricted`, then provide the reviewer source and steps above.
- Government apps, news apps, health apps, financial features, and data deletion declarations: answer according to actual functionality; do not select categories that do not apply.
- Intellectual property: keep licenses or written authorization for every image, video, channel logo, trademark, and demo stream used in the listing or reviewer source.

## Store assets

- 512 × 512 Play icon, 32-bit PNG, no rounded-corner mask baked in.
- 1024 × 500 feature graphic, JPEG or 24-bit PNG without alpha.
- At least two accurate phone screenshots are included using Lumen UI and no third-party media artwork.
- Because the manifest enables Android TV, an Android TV screenshot and a 320 × 180 TV banner are included.
- Screenshots must match the current UI and must not imply that Lumen includes content.

## Release gates for every version

- [ ] `flutter analyze` passes with no new errors.
- [ ] Unit/widget tests pass.
- [ ] Release AAB builds with the current upload key and increments `versionCode`.
- [ ] The merged release manifest has no `REQUEST_INSTALL_PACKAGES`, storage, contacts, location, microphone, camera, phone, accessibility, VPN, or other undeclared sensitive permission.
- [ ] The Play AAB's merged manifest has `usesCleartextTraffic="false"` and all reviewer URLs are HTTPS.
- [ ] No code downloads or installs APKs; Google Play is the only Android updater.
- [ ] Privacy policy, Data Safety form, store listing, and in-app disclosures match the exact release behavior.
- [ ] Reviewer credentials are active and all core flows work without crashes, dead links, or placeholder content.

## Android TV remote acceptance test

Run this checklist on a physical Android TV/Google TV device before production:

- [ ] Cold launch: complete the legal screen, login, and playlist dialogs using only D-pad, center/select, Back, and the TV keyboard.
- [ ] Navigate from the left signal dock to Home, Movies, Series, Live, Guide, Search, My List, Downloads, and Profile.
- [ ] Traverse every horizontal rail and grid; the focused card must show a clear accent ring/scale and scroll fully into view.
- [ ] Open movie and series details, switch seasons, favorite an item, start playback, and use download controls.
- [ ] Open categories, schedules, customization, appearance, privacy, and confirmation dialogs; Back must dismiss the topmost page or dialog.
- [ ] During playback, verify center toggles play/pause, Left/Right seeks or changes live channel, Up enters control-focus mode, and all player buttons/panels are reachable.
- [ ] Verify Back closes a player panel first, exits focused controls next, minimizes full-screen playback, and only then navigates the page underneath.
- [ ] Verify subtitles, audio tracks, video fit, playback speed, sleep timer, volume, subtitle size/sync, split view, PiP, and fullscreen controls.
- [ ] Leave focus parked on a control for longer than four seconds; player chrome must remain visible while a control owns focus.
- [ ] Resume the app after Home, PiP, sleep, and network interruption; focus must return to a visible control and playback must remain controllable.
