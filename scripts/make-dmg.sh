#!/bin/zsh
# Package Nocci as a disk image to share: Nocci.app, an Applications shortcut to drag it into, and a Read Me.
# Signed ad-hoc by default, so no personal certificate (and its Apple ID email) is embedded in a copy you hand out.
# Not notarized: the first open needs System Settings › Privacy & Security › Open Anyway (the Read Me says how).
# For a notarized download anyone can open, use scripts/release.sh instead.
#
# Usage: scripts/make-dmg.sh            (NOCCI_SIGN_IDENTITY to sign with a certificate instead)
set -euo pipefail

cd "${0:A:h}/.."
version="$(plutil -extract CFBundleShortVersionString raw Resources/Info.plist)"
dmg="build/Nocci-$version.dmg"
staging="build/dmg"

scripts/build-app.sh release

rm -rf "$staging" "$dmg"
mkdir -p "$staging"
ditto build/Nocci.app "$staging/Nocci.app"
# Re-sign only the copy, so your own build/Nocci.app keeps its signature (and its permissions).
# Remove the old signature first: re-signing in place can leave the old certificate's bytes (your name and
# Apple ID email) in the binary. Strip debug symbols too, since they record this Mac's build paths.
copy_bin="$staging/Nocci.app/Contents/MacOS/Nocci"
codesign --remove-signature "$copy_bin"
strip -S -x "$copy_bin"
codesign --force --entitlements Resources/Nocci.entitlements --sign "${NOCCI_SIGN_IDENTITY:--}" "$staging/Nocci.app"
# Refuse to package anything that still names this Mac's user or a signing identity.
if LC_ALL=C grep -a -q -E "$HOME|Apple Development:|Developer ID Application:" -r "$staging/Nocci.app" \
    && [[ -z ${NOCCI_SIGN_IDENTITY:-} ]]; then
    echo "make-dmg: personal data left in the app copy; not packaging it" >&2
    exit 1
fi
ln -s /Applications "$staging/Applications"
cat > "$staging/Read Me First.txt" <<'EOF'
Nocci shows your Mac's notifications in the notch.

Install
1. Drag Nocci into the Applications folder.
2. Open Applications and double-click Nocci. macOS says it can't be opened, because Nocci isn't
   notarized by Apple yet. Click Done.
3. Open System Settings › Privacy & Security, scroll down, and click "Open Anyway" next to the
   Nocci message. Confirm with your password or Touch ID.
4. Nocci opens with a setup guide that walks you through the rest. It needs Full Disk Access to
   read your notifications. They stay on your Mac and are never sent anywhere.

Using it
- New notifications grow out of the notch. Hover over the notch to see them all.
- Right-click the notch, or use the menu bar icon, for Settings.
- To stop the usual banners in the top right: System Settings › Notifications › pick an app ›
  turn off "Desktop" (keep "Notification Center" on).

Requires macOS 14 or later.
EOF

hdiutil create -volname "Nocci" -srcfolder "$staging" -ov -format UDZO "$dmg" >/dev/null
rm -rf "$staging"
echo "Ready: $dmg ($(du -h "$dmg" | cut -f1))"
