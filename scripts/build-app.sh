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

codesign --force --sign - "$app"
echo "Built $app"
