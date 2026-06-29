# Lumen — Store Listing Kit

Everything needed to publish Lumen on free Android app stores. The text/graphics
also live under `fastlane/metadata/android/en-US/` (the standard structure that
F-Droid/IzzyOnDroid and many tools read).

## Assets
- **Icon**: `fastlane/metadata/android/en-US/images/icon.png` (512×512)
- **Feature graphic**: `fastlane/metadata/android/en-US/images/featureGraphic.png` (1024×500)
- **Screenshots**: capture from a phone or emulator and drop into
  `fastlane/metadata/android/en-US/images/phoneScreenshots/` (1.png, 2.png, …).
  Recommended shots: Home (immersive hero), TV Guide grid, a Movie/Series detail,
  the video player with controls, Downloads, Profile → Appearance (accent picker).
- **App name**: Lumen
- **Category**: Video Players & Editors / Entertainment
- **Content rating**: typically Teen/12+ (user-supplied media)

## Short description (≤ 80 chars)
> A premium player for your own IPTV — Live TV, Movies & Series. Bring your playlist.

## Full description
See `fastlane/metadata/android/en-US/full_description.txt` (copy-paste ready).

## Download / repo
- Releases (signed APKs): https://github.com/Talha-Ashraf420/Lumen-App/releases/latest
- Repo: https://github.com/Talha-Ashraf420/Lumen-App

---

## Where to publish (free)

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

### Not currently viable
- **F-Droid / IzzyOnDroid**: require FOSS + Fastlane metadata (we have the
  metadata) **but cap a single APK at ~30 MB** — Lumen is ~97 MB (libmpv), so it
  won't qualify without major slimming.
- **Google Play**: $25 one-time fee (not free) and frequently rejects IPTV apps.

---

## Compliance notes
- Lumen ships **no content** — it's a client for the user's own subscription/
  playlist. Keep that framing prominent in every listing (it's in the full
  description and in-app).
- Use the **signed release builds** from CI (stable key, incrementing
  versionCode) so updates install cleanly across stores.
