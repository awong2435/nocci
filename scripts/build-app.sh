#!/bin/zsh
# Build Nocci and wrap it into build/Nocci.app.
# Usage: scripts/build-app.sh [release|debug]   (default: release)
#   release: optimized, universal (Apple Silicon and Intel)
#   debug:   faster to build, this Mac's architecture only, includes debug-only tools (--render-media)
set -euo pipefail

cd "${0:A:h}/.."
config="${1:-release}"

if [[ $config == release ]]; then
    arch_flags=(--arch arm64 --arch x86_64)
else
    arch_flags=()
fi
swift build -c "$config" $arch_flags
bin_dir="$(swift build -c "$config" $arch_flags --show-bin-path)"

app="build/Nocci.app"
rm -rf "$app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
cp "$bin_dir/Nocci" "$app/Contents/MacOS/Nocci"
cp Resources/Info.plist "$app/Contents/Info.plist"
cp Resources/AppIcon.icns "$app/Contents/Resources/AppIcon.icns"

# Sign with a stable identity so Full Disk Access survives rebuilds: NOCCI_SIGN_IDENTITY if set,
# otherwise the first "Apple Development" certificate in the keychain, otherwise ad-hoc.
identity="${NOCCI_SIGN_IDENTITY:-$(security find-identity -v -p codesigning | awk -F'"' '/Apple Development/ { print $2; exit }')}"
# The entitlement lets Nocci send Apple Events (Spotify, Music) under the hardened runtime.
sign_flags=(--force --entitlements Resources/Nocci.entitlements)
if [[ $identity == "Developer ID Application"* ]]; then
    # Notarization requires the hardened runtime and a secure timestamp.
    sign_flags+=(--options runtime --timestamp)
fi
codesign $sign_flags --sign "${identity:--}" "$app"
echo "Signed with: ${identity:-ad-hoc}"
echo "Built $app ($(lipo -archs "$app/Contents/MacOS/Nocci"))"
