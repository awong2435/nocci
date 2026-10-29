#!/bin/zsh
# Build Nocci for a GitHub Release: universal build, Developer ID signature, Apple notarization, stapled
# ticket, zipped. See RELEASING.md for the one-time setup.
#
# Usage: scripts/release.sh
#   NOCCI_SIGN_IDENTITY   "Developer ID Application: Name (TEAMID)"; default: the first one in the keychain
#   NOCCI_NOTARY_PROFILE  notarytool keychain profile; default: nocci-notary
set -euo pipefail

cd "${0:A:h}/.."

bundle_id="$(plutil -extract CFBundleIdentifier raw Resources/Info.plist)"
if [[ $bundle_id == local.* ]]; then
    echo "error: CFBundleIdentifier is still the placeholder '$bundle_id'. Set the real app ID in Resources/Info.plist first." >&2
    exit 1
fi

identity="${NOCCI_SIGN_IDENTITY:-$(security find-identity -v -p codesigning | awk -F'"' '/Developer ID Application/ { print $2; exit }')}"
if [[ $identity != "Developer ID Application"* ]]; then
    echo "error: no Developer ID Application certificate found. Install one, or set NOCCI_SIGN_IDENTITY." >&2
    exit 1
fi
profile="${NOCCI_NOTARY_PROFILE:-nocci-notary}"
version="$(plutil -extract CFBundleShortVersionString raw Resources/Info.plist)"
zip="build/Nocci-$version.zip"

echo "==> Building Nocci $version ($bundle_id)"
NOCCI_SIGN_IDENTITY="$identity" scripts/build-app.sh release
codesign --verify --strict --verbose=2 build/Nocci.app

echo "==> Notarizing (usually a few minutes)"
rm -f "$zip"
ditto -c -k --keepParent build/Nocci.app "$zip"
xcrun notarytool submit "$zip" --keychain-profile "$profile" --wait

echo "==> Stapling and re-zipping"
xcrun stapler staple build/Nocci.app
rm -f "$zip"
ditto -c -k --keepParent build/Nocci.app "$zip"
spctl --assess --type execute --verbose=2 build/Nocci.app

echo "==> Ready: $zip"
echo "Attach it to a GitHub Release tagged v$version."
