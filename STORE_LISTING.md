# Lumen — Store Listing Kit

Reusable listing text and graphics for Google Play and other Android stores.
The canonical copy lives under `fastlane/metadata/android/en-US/`.

## Assets
- **Icon**: `fastlane/metadata/android/en-US/images/icon.png` (512×512)
- **Feature graphic**: `fastlane/metadata/android/en-US/images/featureGraphic.png` (1024×500)
- **Android TV banner**: `fastlane/metadata/android/en-US/images/tvBanner.png` (320×180)
- **Screenshots**: capture from a phone or emulator and drop into
  `fastlane/metadata/android/en-US/images/phoneScreenshots/` (1.png, 2.png, …).
  Recommended shots: Home (immersive hero), TV Guide grid, a Movie/Series detail,
  the video player with controls, Downloads, Profile → Appearance (accent picker).
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
- New personal accounts must complete Google's required closed test before
  production access.

## Other distribution options

### 1. Obtainium (recommended — zero submission)
Not a store: users install + auto-update straight from GitHub Releases.
- Tell users to add this repo in Obtainium: `https://github.com/Talha-Ashraf420/Lumen-App`
- App: https://github.com/ImranR98/Obtainium

### 2. Aptoide (self-publish, no strict review)
1. Create a free account at https://aptoide.com
2. Open **My Store** (in the Aptoide app) or the web dashboard.
3. Upload `Lumen-Android.apk`, paste the short/full description, add icon +
   feature graphic + screenshots.

### 3. APKPure
1. Go to https://apkpure.com and open the developer/upload flow.
2. Upload the APK and listing assets above.

### 4. Uptodown
1. https://uptodown.com → "submit your app".
2. Provide the APK + listing assets; lightly curated.

### Reviewed stores (free account, may reject IPTV)
- Amazon Appstore, Samsung Galaxy Store, Huawei AppGallery. Frame Lumen strictly
  as a **media player (bring your own playlist)** to improve approval odds.

### Current limitation
- **F-Droid / IzzyOnDroid**: require FOSS + Fastlane metadata, while Lumen's
  native video libraries make the current universal APK unusually large.

---

## Compliance notes
- Lumen ships **no content** — it's a client for the user's own subscription/
  playlist. Keep that framing prominent in every listing (it's in the full
  description and in-app).
- Use the **signed release builds** from CI (stable key, incrementing
  versionCode) so updates install cleanly across stores.
