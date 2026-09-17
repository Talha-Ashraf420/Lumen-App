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
- The committed mockups use only Lumen UI and fictional/local test data.
  Regenerate the accurate source captures, then the branded mockups:
  `flutter test --update-goldens tool/store_screenshots_test.dart`
  and `dart run tool/generate_store_mockups.dart`.
- Add further screenshots only when every poster, logo, program name, and media
  item is owned or licensed for store marketing.
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
- Lumen ships **no content** — it's a client for the user's own subscription/
  playlist. Keep that framing prominent in every listing (it's in the full
  description and in-app).
- Use the **signed release builds** from CI (stable key, incrementing
  versionCode) so updates install cleanly in each supported distribution
  channel.
