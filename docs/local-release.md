# Local Android + macOS release

The hosted cross-platform workflow is manual-only; `git push` does not trigger
it. `git push` alone pushes **source code only**. Use the explicit command below
for a release, so failed local tests/builds cannot silently publish an APK.

Requirements on the Mac: Flutter, Xcode, Java 17, Android SDK (including
`apksigner` and `aapt`), `gh` logged in with release-write access, a private
Play upload key configured in `android/key.properties`, and a **distinct**
Community signing key configured in ignored `android/community-key.properties`.
The Community properties use the same `storeFile`, `keyAlias`, `keyPassword`,
and `storePassword` format as the Play properties; `storeFile` is resolved
relative to `android/app` unless absolute. Never commit either private file or
keystore. You can point `LUMEN_COMMUNITY_KEY_PROPERTIES` at another private
location instead. The same Community certificate as earlier releases is
needed for existing APK installs to update in place.

Choose a monotonically increasing build number (greater than the rolling
release's `build:` and at least the `pubspec.yaml` build number). From the repo:

```bash
bash tool/release_local.sh 107
```

This runs analysis/tests, builds and verifies the signed Play `.aab` and
Community `.apk`, builds the macOS app, and stages APK, zip, and SHA-256 files
under `build/local-release/107`. It **does not** push or publish. Inspect/test
the artifacts before committing the source. For an intentional release:

```bash
git add .github/workflows/build.yml .gitignore android/app/build.gradle.kts lib/updater.dart tool/release_local.sh README.md docs/local-release.md
git commit -m "Use local Android and macOS releases"
bash tool/release_local.sh 107 --publish
```

The publish command repeats checks/builds, requires a clean tracked tree and
`main`, pushes the committed source to the `github` remote, replaces **only**
the Android and macOS assets on the existing `latest` release, and updates its
build metadata. Existing Windows/Linux/unsigned iOS assets remain at their
previous build numbers. The new updater respects those per-platform numbers,
but older installed desktop clients that only read `build:` may show a
one-time prompt for an unchanged package. `gh release upload --clobber`
replaces matching assets; an interrupted upload can temporarily leave an asset
unavailable. Check both direct download URLs afterward and retry publication
if necessary. Do not run simultaneous releases.

The Play `.aab` stays private on this computer and is **not** submitted to
Google Play. For a requested Android release, complete the Play track,
Downloader code `4560142`, direct APK resolution, and Discord announcement
checklist in [Android release process](android-release-process.md) separately.
This Mac does not produce new Windows/Linux binaries. Trigger the full hosted
workflow manually or build those on their respective systems when needed.

To investigate the reported $33, inspect GitHub **Billing and licensing →
Usage** by SKU/repository. Standard hosted runner minutes on public repos are
free, but artifact storage can accrue charges and other private repositories or
larger runners may be responsible. Turning off the push trigger prevents new
build artifacts here; it does not erase accrued charges or automatically delete
older workflow artifacts. Set a billing budget and review retained artifacts.
