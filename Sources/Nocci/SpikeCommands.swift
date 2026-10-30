import AppKit
import SwiftUI
import NocciCore

/// M2 spike: one-shot commands that print to stdout and exit instead of showing the panel.
///
/// Run through `open` so macOS attributes Full Disk Access to Nocci rather than to the terminal:
///   open -n -W --stdout "$(tty)" --stderr "$(tty)" build/Nocci.app --args --db-info
///   open -n -W --stdout "$(tty)" --stderr "$(tty)" build/Nocci.app --args --db-dates
///   open -n -W --stdout "$(tty)" --stderr "$(tty)" build/Nocci.app --args --print-recent 10
@MainActor
enum SpikeCommands {
    /// Runs a spike command if one was passed. Returns `false` to continue launching the app normally.
    static func runIfRequested(_ arguments: [String]) -> Bool {
        if arguments.contains("--db-info") {
            run { try source().describeSchema() }
            return true
        }
        if arguments.contains("--db-dates") {
            run { try source().describeDates() }
            return true
        }
        #if DEBUG
        if let index = arguments.firstIndex(of: "--render-media") {
            let directory = arguments.dropFirst(index + 1).first ?? "."
            run { try renderMedia(to: directory) }
            return true
        }
        #endif
        if arguments.contains("--now-playing-status") {
            // Whether macOS's private Now Playing framework answers Nocci itself. Field names only, never values.
            typealias GetInfo = @convention(c) (DispatchQueue, @escaping ([String: Any]?) -> Void) -> Void
            guard let handle = dlopen("/System/Library/PrivateFrameworks/MediaRemote.framework/MediaRemote", RTLD_NOW),
                  let symbol = dlsym(handle, "MRMediaRemoteGetNowPlayingInfo") else {
                print("MediaRemote unavailable")
                return true
            }
            let semaphore = DispatchSemaphore(value: 0)
            nonisolated(unsafe) var result = "no callback in 3 s"
            unsafeBitCast(symbol, to: GetInfo.self)(DispatchQueue.global()) { info in
                result = info.map { "got \($0.count) fields" } ?? "empty"
                semaphore.signal()
            }
            _ = semaphore.wait(timeout: .now() + 3)
            print(result)
            return true
        }
        if let index = arguments.firstIndex(of: "--nc-expand-probe") {
            // Tries an action on one app's stack and reports how many of that app's entries show. Counts only.
            let app = arguments.dropFirst(index + 1).first ?? "Slack"
            let actionName = arguments.dropFirst(index + 2).first ?? "Show Details"
            run { probeStackExpansion(app: app, actionName: actionName) }
            return true
        }
        if let index = arguments.firstIndex(of: "--nc-open-test") {
            // Clicks the newest notification from one app (default: Script Editor, i.e. a test notification) the way
            // Nocci does, and reports whether the panel was moved off-screen and the press worked. No content.
            let bundleID = arguments.dropFirst(index + 1).first ?? "com.apple.ScriptEditor2"
            run {
                guard let item = try source().recent(limit: 100, now: Date()).first(where: { $0.appBundleID.lowercased() == bundleID.lowercased() }) else {
                    return "no \(bundleID) notification"
                }
                var result: Bool?
                Task { @MainActor in result = await NotificationCenterUI.open(notificationID: item.id, appName: item.appName) }
                while result == nil { RunLoop.main.run(until: Date().addingTimeInterval(0.02)) }
                let hide = NotificationCenterUI.lastHide
                return "pressed: \(result!), moved off-screen: \(hide.map { "\($0.moved)" } ?? "panel was already open or a banner was pressed"), window visible for: \(hide.map { "\($0.visibleFor)" } ?? "-"), frontmost: \(NSWorkspace.shared.frontmostApplication?.bundleIdentifier ?? "?")"
            }
            return true
        }
        if let index = arguments.firstIndex(of: "--nc-close-test") {
            // Closes the newest N notifications from Script Editor (test notifications) in Notification Center the
            // way a dismissal in Nocci does, then checks they're gone from the database. Counts only.
            let count = arguments.dropFirst(index + 1).first.flatMap(Int.init) ?? 2
            run {
                let source = try source()
                let items = try source.recent(limit: 200, now: Date()).filter { $0.appBundleID == "com.apple.scripteditor2" }.prefix(count)
                guard !items.isEmpty else { return "no Script Editor notifications" }
                var closed: Int?
                Task { @MainActor in
                    closed = await NotificationCenterUI.close(notificationIDs: items.map(\.id), appNames: Set(items.map(\.appName)))
                }
                while closed == nil { RunLoop.main.run(until: Date().addingTimeInterval(0.02)) }
                var stillThere = items.count
                for _ in 0..<20 {
                    RunLoop.main.run(until: Date().addingTimeInterval(0.25))
                    var existing: Set<String>?
                    Task { existing = try? await source.existingIDs() }
                    while existing == nil { RunLoop.main.run(until: Date().addingTimeInterval(0.02)) }
                    stillThere = items.filter { existing!.contains($0.id) }.count
                    if stillThere == 0 { break }
                }
                return "asked to close \(items.count), closed \(closed!), still in database after: \(stillThere), moved off-screen: \(NotificationCenterUI.lastHide.map { "\($0.moved)" } ?? "not needed")"
            }
            return true
        }
        if arguments.contains("--nc-windows") {
            // Notification Center's windows with the panel as it is: type, frame, whether movable. Changes nothing.
            run {
                guard NotificationCenterUI.isTrusted, let center = NotificationCenterUI.appElement(NotificationCenterUI.notificationCenterID) else {
                    return "no accessibility or Notification Center"
                }
                let windows = (NotificationCenterUI.attribute(center, kAXWindowsAttribute) as [AXUIElement]?) ?? []
                var lines = ["panel open: \(NotificationCenterUI.isPanelOpen()), windows: \(windows.count)"]
                for window in windows {
                    let subrole: String = NotificationCenterUI.attribute(window, kAXSubroleAttribute) ?? "?"
                    var position = CGPoint.zero, size = CGSize.zero
                    if let value: AXValue = NotificationCenterUI.attribute(window, kAXPositionAttribute) { AXValueGetValue(value, .cgPoint, &position) }
                    if let value: AXValue = NotificationCenterUI.attribute(window, kAXSizeAttribute) { AXValueGetValue(value, .cgSize, &size) }
                    var settable: DarwinBoolean = false
                    AXUIElementIsAttributeSettable(window, kAXPositionAttribute as CFString, &settable)
                    lines.append("- \(subrole) at \(Int(position.x)),\(Int(position.y)) \(Int(size.width))x\(Int(size.height)) movable=\(settable.boolValue) children=\(NotificationCenterUI.children(window).count)")
                }
                return lines.joined(separator: "\n")
            }
            return true
        }
        if arguments.contains("--nc-probe") {
            // Opens the Notification Center panel, lists its entries by type and ID match only, closes it.
            run { try probeNotificationCenter() }
            return true
        }
        if arguments.contains("--link-status") {
            // Which recent notifications carry a default-action link, by app and link scheme only (never the link).
            run { try source().describeLinks() }
            return true
        }
        if arguments.contains("--automation-status") {
            // Reads the Automation permission for Music and Spotify without ever asking.
            let semaphore = DispatchSemaphore(value: 0)
            nonisolated(unsafe) var lines: [String] = []
            Task.detached {
                let client = NowPlayingClient()
                for app in MediaApp.allCases {
                    let permission = await client.permission(for: app, ask: false)
                    // Outcome type and error code only; never track details.
                    let outcome: String = switch await client.poll(app) {
                    case .track(let snapshot): "track (\(snapshot.isPlaying ? "playing" : "paused"), artwork host: \(snapshot.artworkURL?.host() ?? "none"))"
                    case .idle: "idle"
                    case .denied: "denied"
                    case .failed(let code): "failed \(code)"
                    }
                    lines.append("\(app.displayName): permission \(permission), poll \(outcome)")
                }
                // System Now Playing: source app and flags only, never the title or artist.
                if let info = await SystemNowPlaying().read() {
                    lines.append("System: app \(info.bundleID), \(info.isPlaying ? "playing" : "paused"), title \(info.title.isEmpty ? "missing" : "present"), duration \(info.duration > 0 ? "known" : "unknown")")
                } else {
                    lines.append("System: nothing")
                }
                semaphore.signal()
            }
            semaphore.wait()
            print(lines.joined(separator: "\n"))
            return true
        }
        if let index = arguments.firstIndex(of: "--print-recent") {
            let limit = arguments.dropFirst(index + 1).first.flatMap(Int.init) ?? 10
            run {
                try source().recent(limit: limit, now: Date()).map(format).joined(separator: "\n\n")
            }
            return true
        }
        return false
    }

    #if DEBUG
    /// Renders the media section (playing, paused, no track) and the compact views to PNGs in `directory`,
    /// using a sample track, for checking the design without a player or permissions.
    @MainActor
    private static func renderMedia(to directory: String) throws -> String {
        func write(_ view: some View, _ name: String) throws {
            let renderer = ImageRenderer(content: view.environment(\.colorScheme, .dark))
            renderer.scale = 2
            guard let image = renderer.nsImage, let tiff = image.tiffRepresentation,
                  let png = NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:]) else { return }
            try png.write(to: URL(filePath: directory).appending(path: name))
        }
        func island(_ content: some View, width: CGFloat) -> some View {
            content.frame(width: width).background(.black, in: RoundedRectangle(cornerRadius: 22))
        }
        let playing = MediaPlugin(), paused = MediaPlugin(), idle = MediaPlugin()
        playing.loadSample(playing: true)
        paused.loadSample(playing: false)
        idle.setActive(false)
        try write(island(MediaSection(plugin: playing), width: 560), "media-playing.png")
        try write(island(MediaSection(plugin: paused), width: 560), "media-paused.png")
        try write(island(MediaSection(plugin: playing), width: 360), "media-narrow.png")
        try write(island(MediaSection(plugin: idle), width: 560), "media-idle.png")
        try write(HStack(spacing: 0) {
            MediaCompactLeading(plugin: playing).frame(width: compactWingWidth)
            Color.clear.frame(width: 209)
            MediaCompactTrailing(plugin: playing).frame(width: compactWingWidth)
        }.frame(height: 38).background(.black, in: Capsule()), "media-compact.png")

        // The list, with made-up notifications (never real ones): collapsed, then with Slack expanded.
        let store = NotificationStore(lastOpened: .distantPast)
        let now = Date()
        func sample(_ id: String, _ app: String, _ name: String, _ title: String, _ subtitle: String?, _ body: String, minutesAgo: Double) -> NotificationItem {
            NotificationItem(id: id, appBundleID: app, appName: name, title: title, subtitle: subtitle, body: body,
                             date: now.addingTimeInterval(-minutesAgo * 60))
        }
        store.ingest([
            sample("1", "com.apple.ScriptEditor2", "Script Editor", "Build finished", nil, "All tests passed.", minutesAgo: 16),
            sample("2", "com.apple.ScriptEditor2", "Script Editor", "Retest", nil, "Watch the notch: this card should grow out of it.", minutesAgo: 54),
            sample("3", "com.apple.ScriptEditor2", "Script Editor", "Test", nil, "Hello from Nocci", minutesAgo: 57),
            sample("4", "com.tinyspeck.slackmacgap", "Slack", "Team", "#general", "Lunch at noon?", minutesAgo: 33),
            sample("5", "com.tinyspeck.slackmacgap", "Slack", "Team", "#random", "Look at this.", minutesAgo: 40),
            sample("6", "com.anthropic.claudefordesktop", "Claude", "Scheduled task completed", nil, "Daily wrapup", minutesAgo: 25),
        ])
        let listState = NotificationListState()
        let previewSettings = NocciSettings(defaults: UserDefaults(suiteName: "nocci-render-\(UUID().uuidString)")!)
        try write(island(NotificationList(store: store, state: listState, notchHeight: 0, scrolls: false)
            .environment(\.nocciSettings, previewSettings), width: 560), "list-collapsed.png")
        previewSettings.quietMode = true
        try write(island(NotificationList(store: store, state: listState, notchHeight: 0, scrolls: false)
            .environment(\.nocciSettings, previewSettings), width: 560), "list-quiet.png")
        listState.expanded = ["com.apple.ScriptEditor2"]
        try write(island(NotificationList(store: store, state: listState, notchHeight: 0, scrolls: false), width: 560), "list-expanded.png")
        return "Rendered to \(directory)"
    }
    #endif

    private static func probeStackExpansion(app: String, actionName: String) -> String {
        guard NotificationCenterUI.isTrusted, let clock = NotificationCenterUI.clockItem() else { return "no accessibility or clock" }
        var lines: [String] = []
        let wasOpen = NotificationCenterUI.isPanelOpen()
        if !wasOpen { _ = NotificationCenterUI.press(clock) }
        for _ in 0..<20 where !NotificationCenterUI.isPanelOpen() { Thread.sleep(forTimeInterval: 0.1) }
        Thread.sleep(forTimeInterval: 0.3)
        func count() -> String {
            let mine = NotificationCenterUI.entries().filter { $0.isFrom(app) }
            return "\(mine.filter { !$0.isStack }.count) entries, \(mine.filter(\.isStack).count) stacks"
        }
        lines.append("\(app) before: \(count())")
        if let stack = NotificationCenterUI.entries().first(where: { $0.isStack && $0.isFrom(app) }) {
            let names = stack.actions.map { $0.components(separatedBy: "\n").first ?? $0 }.joined(separator: "|")
            lines.append("stack actions: \(names)")
            if let action = stack.action(named: actionName) {
                let result = AXUIElementPerformAction(stack.element, action as CFString)
                lines.append("performed \(actionName): \(result.rawValue)")
                Thread.sleep(forTimeInterval: 0.5)
                lines.append("\(app) after: \(count())")
            } else {
                lines.append("no action named \(actionName)")
            }
        } else {
            lines.append("no \(app) stack")
        }
        lines.append("frontmost app: \(NSWorkspace.shared.frontmostApplication?.bundleIdentifier ?? "?")")
        if !wasOpen, NotificationCenterUI.isPanelOpen() { _ = NotificationCenterUI.press(clock) }
        return lines.joined(separator: "\n")
    }

    /// Structure and ID matching only; never titles or bodies.
    private static func probeNotificationCenter() throws -> String {
        var lines = ["accessibility trusted: \(NotificationCenterUI.isTrusted)"]
        guard NotificationCenterUI.isTrusted else { return lines.joined(separator: "\n") }
        guard let clock = NotificationCenterUI.clockItem() else {
            let bar = NotificationCenterUI.appElement(NotificationCenterUI.controlCenterID)
                .flatMap { NotificationCenterUI.attribute($0, "AXExtrasMenuBar") as AXUIElement? }
            let ids = bar.map { NotificationCenterUI.children($0).compactMap { NotificationCenterUI.attribute($0, kAXIdentifierAttribute) as String? } } ?? []
            lines.append("clock not found; menu extras: \(ids.joined(separator: ", "))")
            return lines.joined(separator: "\n")
        }
        let wasOpen = NotificationCenterUI.isPanelOpen()
        lines.append("panel open before: \(wasOpen)")
        if !wasOpen { lines.append("pressed clock: \(NotificationCenterUI.press(clock))") }
        for _ in 0..<20 where !NotificationCenterUI.isPanelOpen() { Thread.sleep(forTimeInterval: 0.1) }
        lines.append("panel open now: \(NotificationCenterUI.isPanelOpen())")
        Thread.sleep(forTimeInterval: 0.3)

        let entries = NotificationCenterUI.entries()
        let databaseIDs = Set((try? source().recent(limit: 200, now: Date()).map(\.id)) ?? [])
        lines.append("entries: \(entries.count) (stacks: \(entries.filter(\.isStack).count)), database IDs: \(databaseIDs.count)")
        for entry in entries.prefix(15) {
            let shape = String((entry.identifier ?? "none").prefix(48).map { $0.isLetter ? "a" : $0.isNumber ? "9" : $0 })
            let id = NotificationCenterUI.normalizedID(entry.identifier)
            lines.append("- \(entry.isStack ? "stack" : "entry") id=\(shape) inDatabase=\(id.map(databaseIDs.contains) ?? false) hasTitle=\(entry.title != nil) actions=\(entry.actions.map { $0.components(separatedBy: "\n").first ?? $0 }.joined(separator: "|"))")
        }
        if !wasOpen {
            Thread.sleep(forTimeInterval: 0.2)
            lines.append("closed again: \(NotificationCenterUI.press(clock))")
        }
        return lines.joined(separator: "\n")
    }

    private static func source() throws -> DatabaseSource {
        guard let url = DatabaseSource.locate() else { throw DatabaseError.notFound }
        return DatabaseSource(url: url, appName: AppInfo.name(for:))
    }

    private static func format(_ item: NotificationItem) -> String {
        let time = item.date.formatted(date: .abbreviated, time: .standard)
        var lines = ["[\(time)] \(item.appName) (\(item.appBundleID))", "  title: \(item.title)"]
        if let subtitle = item.subtitle { lines.append("  subtitle: \(subtitle)") }
        lines.append("  body: \(item.body)")
        return lines.joined(separator: "\n")
    }

    private static func run(_ body: () throws -> String) {
        do { print(try body()) } catch { printError(error) }
    }

    private static func printError(_ error: Error) {
        FileHandle.standardError.write(Data("error: \(error)\n".utf8))
    }
}
