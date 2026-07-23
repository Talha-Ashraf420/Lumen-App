#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_dir="$(cd "$script_dir/.." && pwd)"
properties_file="$repo_dir/android/key.properties"

if [[ ! -f "$properties_file" ]]; then
  echo "Missing android/key.properties. Restore it from the private signing backup."
  exit 1
fi

store_file="$(
  sed -n 's/^storeFile=//p' "$properties_file" | tail -n 1
)"
if [[ -z "$store_file" ]]; then
  echo "android/key.properties does not define storeFile."
  exit 1
fi

if [[ "$store_file" = /* ]]; then
  resolved_store_file="$store_file"
else
  resolved_store_file="$repo_dir/android/app/$store_file"
fi

if [[ ! -f "$resolved_store_file" ]]; then
  echo "Upload keystore not found at the configured path."
  exit 1
fi

if git -C "$repo_dir" ls-files --error-unmatch \
  android/key.properties >/dev/null 2>&1; then
  echo "Refusing to build: android/key.properties is tracked by Git."
  exit 1
fi

if git -C "$repo_dir" ls-files --error-unmatch \
  "android/app/$(basename "$resolved_store_file")" >/dev/null 2>&1; then
  echo "Refusing to build: the upload keystore is tracked by Git."
  exit 1
fi

cd "$repo_dir"
flutter build appbundle --release "$@"

bundle="$repo_dir/build/app/outputs/bundle/release/app-release.aab"
if [[ ! -f "$bundle" ]]; then
  echo "Flutter completed without producing the expected app bundle."
  exit 1
fi

echo "Play bundle: $bundle"
shasum -a 256 "$bundle"
