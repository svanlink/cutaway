#!/bin/bash
# Cutaway release: verify → build → zip → publish → bump the cask.
# Usage: scripts/release.sh 1.0.1
set -euo pipefail
V="${1:?usage: release.sh <version>}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

echo "── verification loop"
xcodegen generate
xcodebuild -project Cutaway.xcodeproj -scheme Cutaway -destination 'platform=macOS' test -only-testing:CutawayTests | grep -q "TEST SUCCEEDED"
./scripts/smoke.sh "" 3

echo "── stamp version"
# The bundle must say what brew says. 1.1.0 and 1.2.0 shipped with the
# plist's original "1.0" because nothing wrote it; now the script does.
# xcodegen rewrites Info.plist from project.yml on every generate, so the
# stamp goes into project.yml (the source) and the plist follows.
sed -i '' -E "s/^( *CFBundle(ShortVersionString|Version): ).*/\1\"$V\"/" project.yml
xcodegen generate
[ "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' Sources/Cutaway/Info.plist)" = "$V" ] || { echo "stamp failed"; exit 1; }
git diff --quiet project.yml Sources/Cutaway/Info.plist || git commit -qm "chore: version $V" project.yml Sources/Cutaway/Info.plist

echo "── release build"
xcodebuild -project Cutaway.xcodeproj -scheme Cutaway -configuration Release -destination 'platform=macOS' build | grep -q "BUILD SUCCEEDED"
# The DerivedData dir that was built from THIS project — never the first one
# alphabetically. A deleted worktree once left an older Timex-* DerivedData dir that
# sorted first, and every smoke run for a day launched its stale binary.
derived_app() {  # $1 = Debug|Release
  local want="$ROOT/Cutaway.xcodeproj" d app newest=""
  for d in "$HOME"/Library/Developer/Xcode/DerivedData/Cutaway-*; do
    app="$d/Build/Products/$1/Cutaway.app"
    [ -d "$app" ] || continue
    if [ "$(/usr/libexec/PlistBuddy -c 'Print :WorkspacePath' "$d/info.plist" 2>/dev/null)" = "$want" ]; then
      echo "$app"; return 0
    fi
    [ -z "$newest" ] || [ "$app/Contents/MacOS/Cutaway" -nt "$newest/Contents/MacOS/Cutaway" ] && newest="$app"
  done
  [ -n "$newest" ] && echo "$newest"
}
REL=$(derived_app Release)
[ -d "$REL" ] || { echo "no Release Cutaway.app for $ROOT"; exit 1; }
echo "release build: $REL"

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
# The tag lands on the STAMPED commit: fast-forward main and push first,
# so the release points at a tree whose bundle says $V.
git branch -f main HEAD && git push -q origin main HEAD
gh release create "v$V" "$ZIP" --title "Cutaway $V" --generate-notes

echo "── verify the published asset"
# What the cask promises must be what a user actually downloads. Checking the
# local zip proves only that the local zip is the local zip; this fetches the
# asset back from the release and compares. (For 1.2.0 and 1.3.0 this was done
# by hand, three ways. A step that matters that much belongs in the script.)
BACK=$(mktemp -d)
gh release download "v$V" -p "Cutaway-$V.zip" -D "$BACK"
PUBLISHED=$(shasum -a 256 "$BACK/Cutaway-$V.zip" | cut -d' ' -f1)
[ "$PUBLISHED" = "$SHA" ] || { echo "PUBLISHED ASSET DOES NOT MATCH: $PUBLISHED != $SHA"; exit 1; }
echo "   asset verified: $SHA"

echo "── bump cask"
TAP=$(mktemp -d)
gh repo clone svanlink/homebrew-tap "$TAP" -- -q
sed -i '' "s/version \".*\"/version \"$V\"/; s/sha256 \".*\"/sha256 \"$SHA\"/" "$TAP/Casks/cutaway.rb"
# A sed that matched nothing is a silent no-op, and a cask still pointing at
# the previous version would install the wrong build while the script says
# "shipped".
grep -q "version \"$V\"" "$TAP/Casks/cutaway.rb" || { echo "cask version not updated"; exit 1; }
grep -q "sha256 \"$SHA\"" "$TAP/Casks/cutaway.rb" || { echo "cask sha not updated"; exit 1; }
git -C "$TAP" -c user.name=vaneickelen -c user.email=vaneickelen.smo91@gmail.com commit -aqm "cutaway $V"
git -C "$TAP" push -q
echo "shipped: brew upgrade --cask cutaway picks up $V"
