# Nocci

Your Mac's notifications, in the notch. New notifications grow out of the notch like the Dynamic Island on iPhone,
then tuck away behind a small green light. Hover over the notch to see them all, grouped by app.

![The notification list, grouped by app](docs/images/list-collapsed.png)

## Features

- **Alerts from the notch.** New notifications grow out of the notch, then collapse. Click one to open its app,
  swipe it up to hide it (it stays in the list).
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

## Requirements

**To run Nocci**

- macOS 14 (Sonoma) or later, on Apple silicon or Intel.
- A MacBook with a notch is best. On other screens, Nocci shows as a small black pill at the top center of the
  screen. You can pick the screen in Settings.
- Full Disk Access, to read your notifications. The setup guide walks you through it.
- Optional:
  - **Accessibility** lets a click open the exact message, and lets clearing a notification in Nocci clear it from
    Notification Center too.
  - The media plugin works with Spotify, Apple Music, or anything else playing on your Mac.

**To build from source**

- Xcode 16 or later, which includes Swift 6. The Command Line Tools alone can compile, but they can't make the
  universal release build or run the tests.
- The Apple Development certificate you get by signing in to Xcode with your Apple ID is optional. Without one,
  Nocci is signed ad-hoc, and macOS forgets its Full Disk Access every time you rebuild.

## Install

**Download:** grab the latest `Nocci-<version>.zip` from [Releases](../../releases), unzip it, and drag Nocci to
Applications. Open it, and the setup guide walks you through permissions.

**Build it yourself** (see Requirements above):

```bash
git clone https://github.com/awong2435/nocci.git
cd nocci && scripts/build-app.sh
mv build/Nocci.app /Applications/ && open /Applications/Nocci.app
```

## Permissions

Nocci asks only for what you use, and the setup guide (menu bar › Setup Guide…) explains each one.

| Permission | Why | Needed? |
|---|---|---|
| Full Disk Access | macOS keeps notifications in a protected database. | Yes |
| Automation (Spotify, Music) | To show what's playing and control playback. Asked the first time you use the controls. | Media plugin only |
| Accessibility | Clicking a notification opens the exact message, and clearing it clears it from Notification Center too. Also play/pause for other apps and Escape to close the island. | Optional |

To stop seeing the usual banners in the top right, turn off **Desktop** for each app in System Settings ›
Notifications (keep **Notification Center** on).

## Using it

- **Hover over the notch** to open the list. Move away to close it, or press Escape.
- **Right-click the notch** (or menu bar › Settings…) for settings.
- **Click** a notification to open it in its app. **Swipe an alert up** to hide it for now; **swipe a list row sideways** to clear it (from macOS's Notification Center too).

## Known limits

- Alerts appear about 6 to 8 seconds after a notification arrives, because macOS saves notifications in batches.
- Without Accessibility, clicking opens the app rather than the exact message, and clearing in Nocci doesn't
  clear macOS's Notification Center.
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

**Secret scan.** A [gitleaks](https://github.com/gitleaks/gitleaks) pre-commit hook blocks commits that add API keys,
tokens, or private keys, and GitHub Actions scans every push. Turn the hook on once per clone:

```bash
brew install gitleaks
git config core.hooksPath .githooks
```

Layout: `Sources/NocciCore` (models, store, database reader, no UI), `Sources/Nocci` (the app),
`Sources/Nocci/Plugins` (plugins, including Media), `Tests/NocciCoreTests`. See `CLAUDE.md` for the project's
rules and `RELEASING.md` for publishing a signed, notarized release.

## License

MIT. See [LICENSE](LICENSE).
