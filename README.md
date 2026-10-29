# Nocci

Your Mac's notifications, in the notch. New notifications grow out of the notch like the Dynamic Island on iPhone,
then tuck away behind a small green light. Hover over the notch to see them all, grouped by app.

![The notification list, grouped by app](docs/images/list-collapsed.png)

## Features

- **Alerts from the notch.** New notifications grow out of the notch, then collapse. Click one to open its app,
  swipe it up to dismiss it.
- **Notification Center in the notch.** Hover over the notch to see everything, grouped by app in stacks.
  Expand a stack, swipe a notification away, or Clear All.
- **Unread light.** A small green light (or a count) beside the notch while something's unread.
- **Media (optional plugin).** What's playing in Spotify, Apple Music, or any other app (YouTube in a browser,
  podcasts), with artwork, a timer you can drag, and controls, styled after the iPhone's Now Playing.
- **Make it yours.** Width (drag the edges), text size, alert duration, hover timing, which screen, and which
  apps can show notifications. Plugins can be turned on, off, and reordered.

<p>
  <img src="docs/images/media-playing.png" width="420" alt="Media player, playing">
  <img src="docs/images/media-compact.png" width="300" alt="Compact media view beside the notch">
</p>

## Privacy

- **Your notifications stay on your Mac.** Nocci reads macOS's notification database read-only, keeps what it
  shows in memory, and never sends notifications anywhere.
- **Message text is never saved.** Nocci saves only your settings, when you last opened the list, and which
  notifications you dismissed.
- **The one network request** is the optional media plugin downloading Spotify album covers from Spotify's own
  image server. Nothing about you or your notifications is sent.

## Install

**Download:** grab the latest `Nocci-<version>.zip` from [Releases](../../releases), unzip it, and drag Nocci to
Applications. Open it, and the setup guide walks you through permissions.

**Build it yourself** (needs macOS 14 or later and Xcode or the Command Line Tools):

```bash
git clone https://github.com/<your-username>/nocci.git
cd nocci && scripts/build-app.sh
mv build/Nocci.app /Applications/ && open /Applications/Nocci.app
```

## Permissions

Nocci asks only for what you use, and the setup guide (menu bar › Setup Guide…) explains each one.

| Permission | Why | Needed? |
|---|---|---|
| Full Disk Access | macOS keeps notifications in a protected database. | Yes |
| Automation (Spotify, Music) | To show what's playing and control playback. Asked the first time you use the controls. | Media plugin only |
| Accessibility | Play/pause for other apps (media keys) and Escape to close the island. | Optional |

To stop seeing the usual banners in the top right, turn off **Desktop** for each app in System Settings ›
Notifications (keep **Notification Center** on).

## Using it

- **Hover over the notch** to open the list. Move away to close it, or press Escape.
- **Right-click the notch** (or menu bar › Settings…) for settings.
- **Click** a notification to open its app; **swipe** it away to dismiss it.

## Known limits

- Alerts appear about 6 to 8 seconds after a notification arrives, because macOS saves notifications in batches.
- Dismissing in Nocci doesn't remove the notification from macOS's Notification Center.
- Reading media from apps other than Spotify and Music uses an undocumented part of macOS and may break with a
  macOS update.

## Development

A Swift Package (no Xcode project), macOS 14+, no dependencies.

```bash
swift build                     # compile
swift test                      # unit tests
scripts/build-app.sh debug      # build/Nocci.app, quick debug build
scripts/build-app.sh            # universal release build
```

Layout: `Sources/NocciCore` (models, store, database reader, no UI), `Sources/Nocci` (the app),
`Sources/Nocci/Plugins` (plugins, including Media), `Tests/NocciCoreTests`. See `CLAUDE.md` for the project's
rules and `RELEASING.md` for publishing a signed, notarized release.

## License

MIT. See [LICENSE](LICENSE).
