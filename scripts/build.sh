#!/bin/bash
# Created 2026-09-15 · gpt-6-astra · Codex
set -euo pipefail
cd "$(dirname "$0")/.."
configuration="${1:-release}"
scratch="${STILL_BUILD_PATH:-.build}"
swift build --build-system native -c "$configuration" --scratch-path "$scratch"
bin_dir="$(swift build --build-system native -c "$configuration" --scratch-path "$scratch" --show-bin-path)"
app="build/Still.app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
cp "$bin_dir/Still" "$app/Contents/MacOS/Still"
cp Resources/Info.plist "$app/Contents/Info.plist"
cp Resources/FocusWebsites.txt "$app/Contents/Resources/"
cp Resources/Still*.aiff "$app/Contents/Resources/"
cp Resources/AppIcon.icns "$app/Contents/Resources/AppIcon.icns"
codesign --force --deep --sign "${CODE_SIGN_IDENTITY:--}" "$app"
# Install to the destination (default /Applications) and remove the build copy
# so no duplicate app shows up in Launchpad or Spotlight.
dest="${STILL_INSTALL_PATH:-/Applications/Still.app}"
mkdir -p "$(dirname "$dest")"
# Preserve the staging bundle when source and destination are equivalent.
if [[ ! "$app" -ef "$dest" ]]; then
  rm -rf "$dest"
  mv "$app" "$dest"
fi
printf 'Built %s\n' "$dest"
