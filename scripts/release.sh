#!/bin/bash
# Cutaway release: verify → build → zip → publish → bump the cask.
# Usage: scripts/release.sh 1.0.1
set -euo pipefail
V="${1:?usage: release.sh <version>}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

echo "── verification loop"
xcodegen generate
xcodebuild -project Timex.xcodeproj -scheme Cutaway -destination 'platform=macOS' test -only-testing:TimexTests | grep -q "TEST SUCCEEDED"
./scripts/smoke.sh "" 3

echo "── release build"
xcodebuild -project Timex.xcodeproj -scheme Cutaway -configuration Release -destination 'platform=macOS' build | grep -q "BUILD SUCCEEDED"
REL=$(ls -d "$HOME"/Library/Developer/Xcode/DerivedData/Timex-*/Build/Products/Release/Cutaway.app | head -1)

echo "── sign (ad-hoc)"
# Ad-hoc signature: no paid Developer ID, but Apple Silicon refuses to run
# fully unsigned binaries, and a valid signature turns Gatekeeper's
# "damaged" error into the right-click-openable "unidentified developer".
codesign --force --deep --sign - "$REL"
codesign --verify --deep --strict "$REL"

echo "── package"
ZIP="/tmp/Cutaway-$V.zip"
ditto -c -k --keepParent "$REL" "$ZIP"
SHA=$(shasum -a 256 "$ZIP" | cut -d' ' -f1)

echo "── publish"
gh release create "v$V" "$ZIP" --title "Cutaway $V" --generate-notes

echo "── bump cask"
TAP=$(mktemp -d)
gh repo clone svanlink/homebrew-tap "$TAP" -- -q
sed -i '' "s/version \".*\"/version \"$V\"/; s/sha256 \".*\"/sha256 \"$SHA\"/" "$TAP/Casks/cutaway.rb"
git -C "$TAP" -c user.name=vaneickelen -c user.email=vaneickelen.smo91@gmail.com commit -aqm "cutaway $V"
git -C "$TAP" push -q
echo "shipped: brew upgrade --cask cutaway picks up $V"
