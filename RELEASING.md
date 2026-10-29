# Releasing Nocci

A release is a signed, notarized `Nocci-<version>.zip` attached to a GitHub Release. People download it, unzip it,
and drag Nocci to Applications. Because it's notarized by Apple, it opens without Gatekeeper warnings.

You need a Mac with Xcode, and an Apple Developer Program membership (for a Developer ID certificate).

## One-time setup

1. **Developer ID certificate.** In Xcode › Settings › Accounts, select your team › Manage Certificates › **+** ›
   **Developer ID Application**. Check it's there:
   ```bash
   security find-identity -v -p codesigning | grep "Developer ID Application"
   ```
2. **Notarization credentials.** Create an app-specific password at [account.apple.com](https://account.apple.com)
   (Sign-In and Security › App-Specific Passwords), then save it in your keychain under the name `nocci-notary`:
   ```bash
   xcrun notarytool store-credentials nocci-notary --apple-id you@example.com --team-id YOURTEAMID
   ```
   It prompts for the password. The script reads it from the keychain; it's never stored in the repo.
3. **Use Xcode's toolchain** (needed for the universal build):
   ```bash
   sudo xcode-select -s /Applications/Xcode.app/Contents/Developer
   ```

## Each release

1. Bump the version in `Resources/Info.plist`: `CFBundleShortVersionString` (for example `0.2`) and
   `CFBundleVersion` (a whole number that always goes up).
2. Build, sign, notarize, staple, and zip:
   ```bash
   scripts/release.sh
   ```
   It stops early if the app ID is still the `local.nocci` placeholder or no Developer ID certificate is found.
3. Create a GitHub Release tagged `v<version>` and attach `build/Nocci-<version>.zip`.

## Notes

- **App ID (`CFBundleIdentifier`).** Don't change it after the first release. macOS ties Full Disk Access and the
  other permissions to it, so a new ID makes every user grant them again.
- **Entitlements.** `Resources/Nocci.entitlements` adds only Apple Events, which the media plugin needs to control
  Spotify and Music under the hardened runtime. No sandbox (the app reads macOS's notification database, which the
  sandbox wouldn't allow).
- **If notarization fails,** see why with `xcrun notarytool log <submission-id> --keychain-profile nocci-notary`.
