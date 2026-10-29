#!/bin/zsh
# Build Tuck and wrap it into build/Tuck.app (ad-hoc signed, no entitlements).
# Usage: scripts/build-app.sh [debug|release]   (default: debug)
set -euo pipefail

cd "${0:A:h}/.."
config="${1:-debug}"

swift build -c "$config"
bin_dir="$(swift build -c "$config" --show-bin-path)"

app="build/Tuck.app"
rm -rf "$app"
mkdir -p "$app/Contents/MacOS"
cp "$bin_dir/Tuck" "$app/Contents/MacOS/Tuck"
cp Resources/Info.plist "$app/Contents/Info.plist"

# Sign with a stable identity so Full Disk Access survives rebuilds: TUCK_SIGN_IDENTITY if set,
# otherwise the first "Apple Development" certificate in the keychain, otherwise ad-hoc.
identity="${TUCK_SIGN_IDENTITY:-$(security find-identity -v -p codesigning | awk -F'"' '/Apple Development/ { print $2; exit }')}"
codesign --force --sign "${identity:--}" "$app"
echo "Signed with: ${identity:-ad-hoc}"
echo "Built $app"
