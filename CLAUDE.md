# Nocci

A small macOS menu bar app that shows notifications in the notch as a Dynamic Island: an alert that grows out of the notch, an unread light beside it, and the full list on hover. Full plan in `PLAN.md`.

## Scope
- The core is notifications only.
- Anything else is an optional plugin: compiled in under `Sources/Nocci/Plugins/`, conforming to `NocciPlugin`, turned on/off and ordered in Settings. Media (`Plugins/Media`) is the only one so far, and it's off by default.
- No files, clipboard, calendar, HUDs, lyrics, AirDrop, VPN, timers, or widgets unless the user asks for a new plugin.

## Privacy
- Read-only, local-only, no network. The core needs one permission (Full Disk Access).
- Plugins may need more (media: Automation for Music/Spotify, Accessibility for media keys), requested only after the user turns the plugin on and uses it. Plugins follow every rule here: no networking, never log or save personal content (track info included).
- Open the notification database read-only. Never write to it or copy it.
- Keep notification text in memory only. Never log it or save it. The only things saved are the "last opened" time and the dismissed IDs.
- No networking code (`URLSession`, `Network`, sockets).

## Stop and ask before
Adding any permission or entitlement, adding any dependency, touching anything that writes to the notification database, or adding any feature outside the plan.

## Build
No Xcode project. A Swift Package, macOS 14+, no dependencies.
- `swift build`: compile
- `swift test`: unit tests (Swift Testing)
- `scripts/build-app.sh`: build and wrap into `build/Nocci.app` (see Signing below)
- `open build/Nocci.app`: run

Use Xcode's toolchain: with only the Command Line Tools selected, incremental `swift test` fails with "plugin for module 'TestingMacros' not found". Either `sudo xcode-select -s /Applications/Xcode.app/Contents/Developer` once, or prefix commands with `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer`.

Layout: `Sources/NocciCore` (no UI: models, store, sources, geometry), `Sources/Nocci` (AppKit/SwiftUI app), `Tests/NocciCoreTests`.

Signing: `scripts/build-app.sh` uses the first "Apple Development" certificate in your keychain (or `NOCCI_SIGN_IDENTITY`), so Full Disk Access survives rebuilds. Without one it signs ad-hoc and the grant resets on every rebuild.

Commit after each milestone you've confirmed works.
