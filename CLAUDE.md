# Nocci

A small macOS menu bar app that shows notifications in the notch as a Dynamic Island: an alert that grows out of the notch, an unread light beside it, and the full list on hover. Full plan in `PLAN.md`.

## Scope
- The core is notifications only.
- Anything else is an optional plugin: compiled in under `Sources/Nocci/Plugins/`, conforming to `NocciPlugin`, turned on/off and ordered in Settings. Media (`Plugins/Media`) is the only one so far, and it's off by default.
- No files, clipboard, calendar, HUDs, lyrics, AirDrop, VPN, timers, or widgets unless the user asks for a new plugin.

## Privacy
- Notifications (the core and the Notifications plugin): read-only, local-only, **no network**. Notification text must never reach any networking code. The core needs one permission (Full Disk Access).
- Other plugins may use the network only for what they need, and only after the user turns them on. Today that's one thing: the media plugin downloads Spotify cover images from Spotify's image server (`*.scdn.co`, https, no cookies or cache). They never send personal data.
- Plugins may need more permissions (media: Automation for Music/Spotify, Accessibility for media keys), requested only after the user turns the plugin on and uses it. Never log or save personal content (track info included).
- Media also reads macOS's system Now Playing (any app, e.g. YouTube in a browser) by running a JavaScript for Automation script in `/usr/bin/osascript` (`SystemNowPlaying.swift`), since Nocci itself is blocked from the private MediaRemote framework. Undocumented and may break on a macOS update; it must fail quietly. Don't load our own code into Apple binaries (the `perl` dylib trick): the user hasn't approved that.
- Clicking a notification uses Accessibility, when granted, to press the same entry in macOS's Notification Center (`NotificationCenterUI.swift`), so the app does exactly what a real click does. It reads entries only to match the clicked one by ID; never log or keep their text. Without Accessibility it falls back to links or opening the app.
- Open the notification database read-only. Never write to it or copy it.
- Keep notification text in memory only. Never log it or save it. The only things saved are the "last opened" time and the dismissed IDs.
- No networking code (`URLSession`, `Network`, sockets) outside `Sources/Nocci/Plugins/Media/MediaPlugin.swift`'s artwork download.

## Stop and ask before
Adding any permission or entitlement, adding any dependency, touching anything that writes to the notification database, or adding any feature outside the plan.

## Build
No Xcode project. A Swift Package, macOS 14+, no dependencies.
- `swift build`: compile
- `swift test`: unit tests (Swift Testing)
- `scripts/build-app.sh`: universal release build into `build/Nocci.app` (see Signing below); `scripts/build-app.sh debug` for a quicker debug build with the debug-only tools (`--render-media`)
- `scripts/release.sh`: signed, notarized release zip; see `RELEASING.md`
- `open build/Nocci.app`: run

Use Xcode's toolchain: with only the Command Line Tools selected, incremental `swift test` fails with "plugin for module 'TestingMacros' not found". Either `sudo xcode-select -s /Applications/Xcode.app/Contents/Developer` once, or prefix commands with `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer`.

Layout: `Sources/NocciCore` (no UI: models, store, sources, geometry), `Sources/Nocci` (AppKit/SwiftUI app), `Tests/NocciCoreTests`.

Signing: `scripts/build-app.sh` uses the first "Apple Development" certificate in your keychain (or `NOCCI_SIGN_IDENTITY`), so Full Disk Access survives rebuilds. Without one it signs ad-hoc and the grant resets on every rebuild.

Commit after each milestone you've confirmed works.
