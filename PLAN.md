> **Scope change (2026-10-29):** the user asked for a plugin system and a media plugin. The core stays notifications-only; extras are optional compiled-in plugins (`NocciPlugin`), toggled and ordered in Settings. "Music" is no longer a non-goal for plugins. See CLAUDE.md for the plugin privacy rules.
>
> **Renamed (2026-10-29):** the app is now **Nocci** (`Sources/Nocci`, `NocciCore`, bundle ID `local.nocci` as a placeholder). "Tuck" below refers to the same app.
>
> **Project note (2026-10-29):** built as a Swift Package with `scripts/build-app.sh` instead of an Xcode project. Xcode is not required. Wherever this plan says `xcodebuild` or "Xcode project file", read `swift build` / `Package.swift`.

# Tuck: build plan v3 (working name)

**Goal:** replace the top-right notification banners with something that lives in the notch. A new notification drops into the notch for a few seconds (you choose, e.g. 10s), then tucks away and leaves an **unread counter**. Hover or click the counter to open your full Notification Center list. Swipe a notification away to dismiss it.

**Non-goals (this is what made the other apps feel bloated):** music, files, clipboard, calendar, HUDs, lyrics, AirDrop, VPN, timers, widgets, anything else.

**Privacy goal:** read-only, local-only, one permission, no network, no copies of your notification text saved anywhere.

---

## 1. How it should behave (the spec)

The panel has four states:

| State | What you see | How you get there |
|---|---|---|
| **Hidden** | Nothing, or just the notch. Hovering the notch area still reveals the list | Nothing unread, or you chose to hide it |
| **Counter** | A small badge by the notch showing the number of unread notifications | There are unread notifications and no alert is showing |
| **Alert** | The newest notification as a wide card dropping from the notch, with full text | A new notification arrives. It stays for the duration you set (5s, 10s, 30s, or until dismissed), then returns to Counter |
| **List** | Your full Notification Center: wide scrolling list, grouped by app, with timestamps and full text | Hover over the notch area (even when nothing is showing), or click the counter. Closes shortly after the mouse leaves, or when you press Escape |

**Rules**
- **Unread** means a notification that arrived after you last opened the list and that you haven't dismissed. Opening the list marks everything as read, and the counter goes to zero.
- **Dismiss** is a swipe on the card (up, or sideways, pick one in M7). Dismissed cards leave the list and don't count as unread.
- **Quiet:** if there's nothing unread and no alert, the panel is invisible, so nothing hovers in the top-right corner.
- Cards are **wide (about 500 to 600 points by default)** and show the **full message text**, with the list scrolling when long.
- **Width is adjustable:** drag either side edge like a normal window. Both sides move equally, so pulling one edge out by 10 px also moves the other edge out by 10 px, and the panel stays centered on the notch. The width is remembered per display.
- Per-app on/off, so only the apps you choose appear.

Open questions to decide later: how it should behave when a Focus mode is on, and whether alerts should repeat for a thread that already has an unread notification.

---

## 2. Decisions to make up front

### A. Where the notifications come from
Showing the full Notification Center needs the history, not just new banners.

| Approach | History? | Permission | Trade-offs |
|---|---|---|---|
| **Read macOS's notification database (recommended)** | Yes | Full Disk Access | One mechanism for history and new items. Slight delay. Location and format vary by macOS version, so verify on your Mac first (M2) |
| Accessibility observer (what DynamicNotch v1.6.2 did) | No, only banners as they appear | Accessibility | Instant, but misses anything that arrived while the app wasn't running. Fragile across macOS updates |

Droppy's setup on your Mac used Full Disk Access and showed Slack notifications in the notch, which suggests the database is readable on your macOS version. That is a hint, not proof, so M2 is a quick test. **Fallback:** if it breaks, build history from captured banners using the Accessibility approach and accept that it only goes back to install time.

**What public sources say about the database (verify on your Mac in M2):**
- **Location:** on macOS Sequoia and later it is reported to be at `~/Library/Group Containers/group.com.apple.usernoted/db2/db`, and Group Containers are protected by a macOS privacy prompt. Earlier versions kept it under `/private/var/folders/...`.
- **Contents:** the open-source Plaso parser describes an `app` table (the bundle identifier) and a `record` table. In `record`, the `data` column is a binary plist whose `req` dictionary holds the title, subtitle, and body, and `delivered_date` is the timestamp.
- **Not confirmed:** whether this layout still holds on your macOS version.

### B. Getting rid of the right-corner banners
In System Settings > Notifications > each app, untick **Desktop** and keep **Notification Center** ticked. No extra permission and nothing to hack. (Sound still plays if you leave it on.)

### C. The window
A borderless, non-activating panel (NSPanel) above the menu bar, centered on the top edge, one per display. On a notched screen it wraps the notch. On other monitors it's a plain pill. SwiftUI for content. It needs mouse tracking for hover and swipe, without stealing keyboard focus from the app you're using.

### D. Swipe and hover
Two-finger trackpad swipes arrive as scroll events with phases, and mouse drags as normal drag gestures. Support both. Droppy's docs mention swipe up to dismiss, so that's a good default.

### D2. Resizable width (drag the edges, both sides move equally)
A borderless panel has no built-in resize handles, so build them: thin invisible strips (about 8 points) on the left and right edges, with the resize cursor on hover.
- **Math:** `newWidth = startWidth + 2 × drag distance`, so each edge moves by the distance you drag. Keep the panel's center fixed on the notch (or the screen center on non-notch displays).
- **Avoid jitter:** measure the drag in screen coordinates (the global mouse position), not inside the panel. Otherwise the panel resizes under your cursor and the numbers feed back on themselves.
- **Limits:** a minimum of about 320 points and a maximum just under the screen width. Double-click an edge to reset to the default.
- **Remember it:** save only the width, per display.
- Height isn't dragged. It grows with content up to a maximum, then the list scrolls.

### D3. Hidden until you hover (like the notch apps do)
The panel is invisible by default and expands when your mouse reaches the notch.
- **Hot zone:** a small transparent, non-activating panel over the notch area (and the counter badge) that only listens for the mouse. It has to exist even when there is nothing to show, otherwise nothing can detect the hover.
- **Timing:** open after a short delay (about 150 to 250 ms) so brushing past doesn't trigger it, and close about 300 to 500 ms after the mouse leaves so it doesn't flicker. Make both delays settings.
- **Optional guard:** a setting to require a modifier key held while hovering. Droppy has a similar "Hold to reveal" option for people who trigger it by accident.
- **Stay open while in use:** keep it open while the mouse is anywhere on the panel, while you're dragging an edge to resize, and during a swipe.
- **Checks to make early:** how it behaves when an app is full screen and the menu bar is hidden, and that mouse tracking works without any extra permission. Both should be tested in M5, not assumed.

### E. What gets saved
Only a "last opened" timestamp and the IDs of dismissed notifications, never message text.

### F. Stack
Swift, SwiftUI and AppKit, Xcode, macOS 14 or later, no third-party packages, **no network entitlement**.

---

## 3. Open-source starting points (read them, don't paste them blindly)

| Project | License | What to take from it | Caveats |
|---|---|---|---|
| **DynamicNotchKit** (MrKai77), Swift package | MIT | Notch window handling, content safe areas, a floating style that kicks in automatically on Macs without a notch, and files for styles and hover behavior | macOS 13+. Maintenance status not checked. I inferred the hover support from file names, so confirm it in the repo |
| **NotchNotification** (Lakr233), Swift package | MIT | The smallest "show a message in the notch" example, works on notchless displays. Good for reading | Shows a message only. No list, hover, or counter |
| **Boring Notch** (TheBoredTeam) | GPL-3.0 | Hover-to-expand, notch sizing across display sizes, settings | Large, with many features you don't want |
| **DynamicNotch** (jackson-storm), main branch | GPL-3.0 | Notch engine, per-display selection, floating capsule on non-notch displays | About 450 Swift files, mostly features you don't want. Its v1.6.2 tag has the Accessibility notification interceptor (the fallback) |
| **Vibe Notch** (farouqaldori) | Apache-2.0 | A small notch app with an expanding panel and action buttons, under a permissive license | Built for Claude Code sessions, macOS 15.6+ |
| **Plaso** `macos_notification_center` parser | Open source (license not checked) | A written description of the notification database tables and fields (see 2A) | A Python forensics tool, so use it as a schema reference only |

**Suggested starting points**
- **Panel and notch:** read DynamicNotchKit and NotchNotification first, since both are MIT and small. Then look at Boring Notch for hover and sizing ideas.
- **Database:** use the Plaso parser and the notes in 2A.
- **Decide at M1:** use DynamicNotchKit as the one allowed dependency (with your approval), or write the panel yourself using it as reference.

**Licensing:** the GPL-3.0 projects are fine to study. If you copy their code into an app you distribute, that app must be GPL too. For personal use this doesn't matter. Prefer the MIT and Apache projects for anything you copy.

---

## 4. Milestones (each one should end with something you can see working)

| # | Milestone | Done when |
|---|---|---|
| M0 | New Xcode project, menu bar app, no Dock icon | App launches and shows only a menu bar icon |
| M1 | Notch panel with hardcoded text | A pill appears at top center of the MacBook screen and does not steal focus |
| **M2** | **Spike: read the notification database** | The console prints the last 10 notifications (app, title, body, time) from your real Notification Center. **If this fails, stop and use the fallback in 2A** |
| M3 | Alert state | Sending yourself a Slack DM drops a wide card from the notch with the full text, then it disappears after the duration. Duration is a setting (5s, 10s, 30s, until dismissed) |
| M4 | Unread counter | After the alert disappears, a badge by the notch shows the unread count and goes up with each new notification |
| M5 | List state with hover reveal | Moving the mouse to the notch area (even with nothing unread) opens the wide list, grouped by app, newest first, with timestamps. It closes shortly after the mouse leaves. Opening it clears the unread count |
| M6 | Resizable width | Dragging a side edge resizes the panel with both edges moving equally, without jitter. The width is remembered, and double-click resets it |
| M7 | Swipe to dismiss | Swiping a card (in the alert or the list) removes it and lowers the count |
| M8 | Open and hide | Clicking a card opens the source app. Escape or moving away closes the list. Optional hotkey to hide everything |
| M9 | Per-app filter | A simple list: tick the apps you want to see |
| M10 | Multiple monitors | Settings choose which display. Panel, badge, and saved width work correctly on each, including non-notch screens |

Do not start the next milestone until the current one works.

**Known limitation:** the app opens the database read-only, so dismissing a card only hides it in your app. It won't clear the real Notification Center. Doing that is a separate, riskier feature, so decide later.

---

## 5. Starter prompt for Claude Code (paste into an empty project folder)

> Build a small macOS menu bar app in Swift (SwiftUI plus AppKit, macOS 14+, no third-party packages, no network access). Its job is to replace the top-right notification banners: when a notification arrives it drops into a wide card from the notch for a configurable duration, then collapses into an unread counter badge by the notch. Hovering the counter opens my full Notification Center list. Swiping a card dismisses it. Do NOT add music, files, clipboard, calendar, or any other feature.
>
> Start with milestones M0 and M1 only: a menu bar app with no Dock icon, and a borderless non-activating NSPanel above the menu bar, centered on the top edge of the main display, showing the text "Hello". On a notched MacBook screen it should sit around the notch. Detect the notch using NSScreen safe area insets. Explain how to run it and what to check, then stop and wait for me.

For **M2**, use: "Find where macOS stores notifications on this machine, open it read-only, and print the last 10 notifications (app name, title, body, time) to the console. Never write to it, never copy it, never send anything over the network. Tell me which permission it needs and what the file path is."

For each later milestone, paste its row from the table plus: "Keep the change small. Don't add features I didn't ask for. Tell me what permissions are needed."

---

## 6. Risks and guardrails
- **Database format can change with a macOS update.** There is no supported API. Expect to patch it occasionally.
- **The database holds every notification you receive,** including prod alerts and DMs. Open it read-only, keep results in memory only, never save a copy, never log message contents, and keep the network entitlement off.
- **Full Disk Access is a big permission.** Grant it only to your own build, and revoke it when you stop using the app.
- **Latency:** the database may update a few seconds after a notification arrives, so alerts could lag slightly behind the old banners. M3 is where you'll find out whether that's acceptable.
- **Building locally in Xcode** avoids the Gatekeeper warning. No paid Apple Developer account is needed for personal use.
- **Start at login:** add a login item once it works.
- Commit to git after every working milestone so you can roll back when the AI breaks something.

---

## 7. Running this with a project-manager agent and subagents

**Scope warning:** this app is small, and most milestones depend on the one before. Fifteen agents working at once would mostly produce merge conflicts, especially in the Xcode project file. **Plan for 5 to 7 agents at a time, and let the PM add more only if there's work that is truly independent.**

### Requirements that agents can't satisfy on their own
- **Claude Code has to run on your Mac with Xcode installed** (not a cloud or Linux session), so the agents can run `xcodebuild`. AppKit and SwiftUI can't be compiled on Linux. Check with `xcodebuild -version` before starting.
- **Permissions are yours to grant.** Full Disk Access for the M2 spike (to whichever app runs it) has to be granted by you in System Settings.
- **Feel needs a human.** Hover timing, resize, swipe, and multi-monitor behavior can't be judged by tests. See the checkpoints below.

### Set up the structure first (so agents don't collide)
- One **Swift package** (`TuckCore`) holding everything that has no UI: the model, the store, the source protocol, and a mock source. One **app target** holding the panel and SwiftUI views. Agents work in different folders.
- **One agent owns the Xcode project file.** Nobody else edits it.
- One git branch (or worktree) per agent. The PM merges after each milestone and runs the build.

### Claude Code setup
- **Models:** Opus as the PM, **Sonnet 5.5 for the worker subagents**. That's fine at this scope. The PM should write the contracts below itself rather than delegate them, since every worker depends on them. Consider running the Reviewer on Opus too, since it makes the privacy calls.
- Save this file in the project root as `PLAN.md`, and add a short `CLAUDE.md` that repeats only the non-goals, the privacy goal, and the "stop and ask" rules. Every subagent then sees the guardrails without reading the whole plan.
- Have each worker use its own git worktree so branches don't touch each other's files.

### Contracts to define on day one (the PM writes these, everyone codes against them)
- `NotificationItem`: id, app bundle ID, app name, title, subtitle, body, date.
- `NotificationSource`: `recent(limit:)` and a stream of new items. Implementations: `MockSource` (fake data) and `DatabaseSource` (real).
- `NotificationStore`: items, unread count, dismissed IDs, last-opened time. Methods: `markAllRead()` and `dismiss(id)`.
- `PanelState`: hidden, counter, alert, list.
- Settings keys: alert duration, panel width per display, hover delays, per-app on/off.

The **MockSource is what unblocks everyone**: UI work doesn't wait for the database spike.

### Workstreams
| Agent | Owns | Milestones |
|---|---|---|
| 1. Shell | Xcode project, menu bar app, panel, notch detection, hover hot zone | M0, M1, part of M5 |
| 2. Data | `DatabaseSource`: find and read the notification database read-only, live updates | M2, M4 data side |
| 3. State | `NotificationStore` logic, unread rules, alert timer, with unit tests | M3 and M4 logic |
| 4. Views | Alert card, counter badge, wide list, grouped by app, full text (against the MockSource) | M3, M4, M5 UI |
| 5. Interaction | Symmetric edge-drag resize, swipe to dismiss, click to open app | M6, M7, M8 |
| 6. Settings | Per-app filter, settings window, multiple monitors | M9, M10 |
| 7. Reviewer | Privacy and scope checks, code review, tests, release notes | every milestone |

**Reviewer checks, every milestone:** no network entitlement or network calls, the database is opened read-only, no message text is logged or saved, nothing outside the non-goals was added. The reviewer can reject a merge.

### Gates and human checkpoints
1. **M2 is the gate.** Everything else can start with the MockSource, but whether the real data source works decides the final architecture. If M2 fails, the PM switches to the Accessibility fallback in section 2A.
2. **You check, in person:** (a) M2: the printed notifications match your real Notification Center, (b) M3: the alert drops in and the delay feels acceptable, (c) M5/M6: hover timing and resize feel right, (d) M7: swipe feels natural, (e) M10: both monitors.
3. **Stop and ask you** before: adding any permission, adding any dependency, touching anything that writes to the notification database, or any feature outside this plan.

### Kickoff prompt for the PM agent
> You are the project manager for "Tuck", a small macOS app. Read the attached plan (sections 1 to 7) fully before doing anything. Run at most 7 subagents at a time, using Sonnet 5.5 for the workers while you stay on Opus as PM. First, set up the Swift package and the contracts in section 7 and get my approval of them. Then assign the workstreams. Each agent works on its own branch and folder; only one agent edits the Xcode project file. After every milestone, the Reviewer agent runs the privacy and scope checks, and you build with xcodebuild before merging. The app must run on this Mac. Pause and ask me at every human checkpoint and before adding any permission, dependency, or out-of-scope feature. Keep a short running log of what is done, what is blocked, and what you need from me.
