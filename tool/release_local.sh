#!/usr/bin/env bash
set -euo pipefail

# Build both signed Android channels and macOS on this Mac. Hosted CI is the
# default; local publication is only for when hosted push releases are off.
repo_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repo_dir"

if [[ $# -lt 1 || $# -gt 2 || ! "${1:-}" =~ ^[1-9][0-9]*$ ||
      ( $# -eq 2 && "$2" != --publish ) ]]; then
  echo 'Usage: bash tool/release_local.sh BUILD_NUMBER [--publish]' >&2
  exit 2
fi
build_number="$1"
publish="${2:-}"
pubspec_number="$(sed -nE 's/^version: [^+]+\+([0-9]+).*/\1/p' pubspec.yaml | head -n 1)"
if [[ -z "$pubspec_number" || "$build_number" -lt "$pubspec_number" ]]; then
  echo "Build number must be at least pubspec.yaml's $pubspec_number." >&2
  exit 1
fi

play_properties="$repo_dir/android/key.properties"
community_properties="${LUMEN_COMMUNITY_KEY_PROPERTIES:-$repo_dir/android/community-key.properties}"
if [[ ! -f "$play_properties" || ! -f "$community_properties" ]]; then
  echo 'Both private Play (android/key.properties) and Community signing properties are required.' >&2
  echo 'Set LUMEN_COMMUNITY_KEY_PROPERTIES or restore android/community-key.properties privately.' >&2
  exit 1
fi

keystore_for() {
  local property_file="$1" store_file
  store_file="$(sed -n 's/^storeFile=//p' "$property_file" | tail -n 1)"
  [[ -n "$store_file" ]] || { echo 'Missing storeFile in private signing properties.' >&2; return 1; }
  if [[ "$store_file" = /* ]]; then
    printf '%s\n' "$store_file"
  else
    printf '%s\n' "$repo_dir/android/app/$store_file"
  fi
}
play_keystore="$(keystore_for "$play_properties")"
community_keystore="$(keystore_for "$community_properties")"
if [[ ! -f "$play_keystore" || ! -f "$community_keystore" ]] ||
   cmp -s "$play_keystore" "$community_keystore"; then
  echo 'Both distinct private keystores must exist; never sign Community with the Play key.' >&2
  exit 1
fi
for private_file in "$play_properties" "$community_properties" "$play_keystore" "$community_keystore"; do
  if git ls-files --error-unmatch "$private_file" >/dev/null 2>&1; then
    echo 'Refusing to release: a private signing file is tracked by Git.' >&2
    exit 1
  fi
done

previous_body=''
previous_build=''
if [[ "$publish" == --publish ]]; then
  if grep -Eq '^[[:space:]]+push:' .github/workflows/build.yml; then
    echo 'Hosted push releases are enabled. Refusing a concurrent local publication.' >&2
    echo 'Disable that workflow trigger first, commit it, then retry --publish.' >&2
    exit 1
  fi
  command -v gh >/dev/null || { echo 'Install GitHub CLI (gh) before publishing.' >&2; exit 1; }
  gh auth status >/dev/null
  [[ "$(git branch --show-current)" == main ]] || { echo 'Publish from main only.' >&2; exit 1; }
  git diff --quiet && git diff --cached --quiet || {
    echo 'Commit tracked changes before publishing; the release must match a commit.' >&2
    exit 1
  }
  previous_body="$(gh release view latest --repo Talha-Ashraf420/Lumen-App --json body --jq .body)"
  previous_build="$(printf '%s\n' "$previous_body" | sed -nE 's/^build: ([0-9]+).*/\1/p' | head -n 1)"
  [[ -n "$previous_build" && "$build_number" -gt "$previous_build" ]] || {
    echo 'Build number must exceed the currently published release build.' >&2
    exit 1
  }
  for asset in Lumen-Windows.zip Lumen-Linux-x64.tar.gz Lumen-iOS-unsigned.zip; do
    if ! gh release view latest --repo Talha-Ashraf420/Lumen-App --json assets --jq '.assets[].name' | grep -Fxq "$asset"; then
      echo "The existing $asset is missing; refusing a partial rolling release." >&2
      exit 1
    fi
  done
fi

command -v flutter >/dev/null || { echo 'Flutter is required.' >&2; exit 1; }
command -v jarsigner >/dev/null || { echo 'Java jarsigner is required.' >&2; exit 1; }
sdk_root="${ANDROID_SDK_ROOT:-${ANDROID_HOME:-$HOME/Library/Android/sdk}}"
apksigner="$(find "$sdk_root/build-tools" -type f -name apksigner 2>/dev/null | sort | tail -n 1)"
[[ -x "$apksigner" ]] || { echo 'Android SDK apksigner is required.' >&2; exit 1; }
aapt="$(dirname "$apksigner")/aapt"
[[ -x "$aapt" ]] || { echo 'Android SDK aapt is required.' >&2; exit 1; }

flutter pub get
flutter analyze --no-fatal-infos
flutter test

# The Play artifact stays local; submission to any Play track is separate.
bash tool/build_play_aab.sh --build-number="$build_number" --dart-define="APP_BUILD=$build_number"
play_bundle='build/app/outputs/bundle/release/app-release.aab'
jarsigner -verify "$play_bundle"
unzip -p "$play_bundle" base/manifest/AndroidManifest.xml | strings | grep -Fq 'com.talhaashraf.lumen' || {
  echo 'Play AAB package identity is wrong.' >&2; exit 1;
}

ORG_GRADLE_PROJECT_lumenSigningPropertiesFile="$community_properties" \
  ORG_GRADLE_PROJECT_lumenCommunityBuild=true \
  flutter build apk --release --build-number="$build_number" --dart-define="APP_BUILD=$build_number"
community_apk='build/app/outputs/flutter-apk/app-release.apk'
"$apksigner" verify --verbose --print-certs "$community_apk"
"$aapt" dump badging "$community_apk" | grep -Fq "package: name='com.talhaashraf.lumen.community'" || {
  echo 'Community APK package identity is wrong.' >&2; exit 1;
}

flutter config --enable-macos-desktop
flutter build macos --release --dart-define="APP_BUILD=$build_number"
mac_app='build/macos/Build/Products/Release/Lumen.app'
[[ -d "$mac_app" ]] || { echo 'Expected Lumen.app was not built.' >&2; exit 1; }

dist_dir="$repo_dir/build/local-release/$build_number"
mkdir -p "$dist_dir"
cp "$community_apk" "$dist_dir/Lumen-Android.apk"
ditto -c -k --sequesterRsrc --keepParent "$mac_app" "$dist_dir/Lumen-macOS.zip"
for asset in "$dist_dir/Lumen-Android.apk" "$dist_dir/Lumen-macOS.zip"; do
  shasum -a 256 "$asset" > "$asset.sha256"
done
echo "Verified builds are ready in $dist_dir (Play AAB remains private)."

if [[ "$publish" != --publish ]]; then
  echo 'Nothing was pushed or published. Re-run with --publish after checking the builds.'
  exit 0
fi

# Retained platforms keep their actual older build metadata. New clients read
# these platform fields; older clients only understand the generic build line.
platform_build() {
  local key="$1" value
  value="$(printf '%s\n' "$previous_body" | sed -nE "s/^build-$key: ([0-9]+).*/\\1/p" | head -n 1)"
  printf '%s\n' "${value:-$previous_build}"
}
windows_build="$(platform_build windows)"
linux_build="$(platform_build linux)"
ios_build="$(platform_build ios)"

git push github main
gh release upload latest \
  "$dist_dir/Lumen-Android.apk" "$dist_dir/Lumen-Android.apk.sha256" \
  "$dist_dir/Lumen-macOS.zip" "$dist_dir/Lumen-macOS.zip.sha256" \
  --clobber --repo Talha-Ashraf420/Lumen-App
gh release edit latest --repo Talha-Ashraf420/Lumen-App \
  --title "Build $build_number" \
  --notes "build: $build_number
build-android: $build_number
build-macos: $build_number
build-windows: $windows_build
build-linux: $linux_build
build-ios: $ios_build

Locally built and verified Community Android and macOS packages.
The signed Play AAB was built locally but has NOT been submitted to Google Play.
Windows, Linux and unsigned iOS packages are retained from their earlier builds.
Older desktop installations may still display a new-release prompt for this
partial rollout; use the matching platform build number above when comparing."

gh release view latest --repo Talha-Ashraf420/Lumen-App --json assets --jq '.assets[].name' |
  grep -Fxq 'Lumen-Android.apk'
gh release view latest --repo Talha-Ashraf420/Lumen-App --json assets --jq '.assets[].name' |
  grep -Fxq 'Lumen-macOS.zip'
echo 'Rolling release updated. Check both direct download URLs, Downloader code 4560142, and announce on Discord before calling the Android release complete.'
