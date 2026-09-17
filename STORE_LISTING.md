# Lumen — Store Listing Kit

Reusable listing text and graphics for Google Play.
The canonical copy lives under `fastlane/metadata/android/en-US/`.

## Assets
- **Icon**: `fastlane/metadata/android/en-US/images/icon.png` (512×512)
- **Feature graphic**: `fastlane/metadata/android/en-US/images/featureGraphic.png` (1024×500)
- **Android TV banner**: `fastlane/metadata/android/en-US/images/tvBanner.png` (320×180)
- **Phone screenshots**:
  `fastlane/metadata/android/en-US/images/phoneScreenshots/`
- **Android TV screenshots**:
  `fastlane/metadata/android/en-US/images/tvScreenshots/`
- Use only screenshots captured from the actual Android app and reproducible
  during Google Play review. The verified TV set is in
  `store_assets/play_store/tv/verified_2026-09-17/` and staged under Fastlane.
  Older generated TV mockups were rejected for showing a catalog absent from
  the app and must not be re-uploaded. Recapture from the reviewed build after
  any substantial UI or demo-content change.
- Add further screenshots only when the depicted features and content are
  present in the reviewed build and marketing rights are clear.
- **App name**: Lumen
- **Category**: Video Players & Editors / Entertainment
- **Content rating**: typically Teen/12+ (user-supplied media)

## Short description (≤ 80 chars)
> Private media player for your own authorized playlists and services.

## Full description
See `fastlane/metadata/android/en-US/full_description.txt` (copy-paste ready).

## Download / repo
- Releases (signed APKs): https://github.com/Talha-Ashraf420/Lumen-App/releases/latest
- Repo: https://github.com/Talha-Ashraf420/Lumen-App

---

## Google Play

- Use `docs/play-store-submission.md` for the release gates.
- Use `docs/play-console-answers.md` for the Console declarations.
- Use `docs/reviewer-access-template.md` for private review credentials.
- Upload an AAB signed with the private upload key and enroll in Google Play App
  Signing.
- Production access has been approved, but the first production release has
  not been published yet. Do not describe the Play listing as publicly
  available until the production rollout is live.

## Community APK distribution

The separately signed Community APK is published on GitHub Releases and is
available through Downloader code `4560142`. Do not advertise third-party
store listings unless they have actually been published and verified.

---

## Compliance notes
- Lumen includes a **small fictional offline demo** but does not supply an
  IPTV subscription or real content catalog. Real media comes only from the
  user's own authorized source. Keep that distinction explicit in listing copy.
- Use the **signed release builds** from CI (stable key, incrementing
  versionCode) so updates install cleanly in each supported distribution
  channel.
