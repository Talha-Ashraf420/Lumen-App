# Local Android + macOS release

The hosted cross-platform workflow runs on pushes to `main` and normally
publishes the release. This local command is a **backup** for building Android
and macOS on a Mac. A normal `git push` starts GitHub Actions, so do not run a
local publication at the same time as its release job.

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
the artifacts. The optional `--publish` path is blocked while the workflow's
push trigger is enabled, to avoid two jobs overwriting the rolling release.
Use it only after intentionally disabling hosted push releases and committing
that workflow change.

The backup publish command repeats checks/builds, requires a clean tracked tree and
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

The billing screenshot showed roughly $34 gross usage covered by roughly $34
of included usage/discounts, not a $34 bill. Standard hosted runner minutes
on public repos are free; storage or other accounts can still incur charges.
Review **Billing and licensing → Usage** by SKU/repository and set an alert.
