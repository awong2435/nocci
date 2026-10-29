# Tuck

A small macOS menu bar app that shows notifications in the notch: an alert card that drops down, then an unread counter, then a hover list. Full plan in `PLAN.md`.

## Non-goals
No music, files, clipboard, calendar, HUDs, lyrics, AirDrop, VPN, timers, widgets, or any other feature outside `PLAN.md`.

## Privacy
- Read-only, local-only, one permission (Full Disk Access, M2 onward), no network.
- Open the notification database read-only. Never write to it or copy it.
- Keep notification text in memory only. Never log it or save it. The only things saved are the "last opened" time and the dismissed IDs.
- No networking code (`URLSession`, `Network`, sockets).

## Stop and ask before
Adding any permission or entitlement, adding any dependency, touching anything that writes to the notification database, or adding any feature outside the plan.

## Build
No Xcode project. A Swift Package, macOS 14+, no dependencies.
- `swift build`: compile
- `swift test`: unit tests (Swift Testing)
- `scripts/build-app.sh`: build and wrap into `build/Tuck.app` (ad-hoc signed)
- `open build/Tuck.app`: run

Layout: `Sources/TuckCore` (no UI: models, store, sources, geometry), `Sources/Tuck` (AppKit/SwiftUI app), `Tests/TuckCoreTests`.

Commit after each milestone you've confirmed works.
