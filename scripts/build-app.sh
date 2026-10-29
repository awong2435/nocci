#!/bin/zsh
# Build Nocci and wrap it into build/Nocci.app (ad-hoc signed, no entitlements).
# Usage: scripts/build-app.sh [debug|release]   (default: debug)
set -euo pipefail

cd "${0:A:h}/.."
config="${1:-debug}"

swift build -c "$config"
bin_dir="$(swift build -c "$config" --show-bin-path)"

app="build/Nocci.app"
rm -rf "$app"
mkdir -p "$app/Contents/MacOS"
cp "$bin_dir/Nocci" "$app/Contents/MacOS/Nocci"
cp Resources/Info.plist "$app/Contents/Info.plist"
mkdir -p "$app/Contents/Resources"
cp Resources/AppIcon.icns "$app/Contents/Resources/AppIcon.icns"

# Sign with a stable identity so Full Disk Access survives rebuilds: NOCCI_SIGN_IDENTITY if set,
# otherwise the first "Apple Development" certificate in the keychain, otherwise ad-hoc.
identity="${NOCCI_SIGN_IDENTITY:-$(security find-identity -v -p codesigning | awk -F'"' '/Apple Development/ { print $2; exit }')}"
codesign --force --sign "${identity:--}" "$app"
echo "Signed with: ${identity:-ad-hoc}"
echo "Built $app"
