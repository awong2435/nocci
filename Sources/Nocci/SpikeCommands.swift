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
        try write(island(NotificationList(store: store, state: listState, notchHeight: 0, scrolls: false), width: 560), "list-collapsed.png")
        listState.expanded = ["com.apple.ScriptEditor2"]
        try write(island(NotificationList(store: store, state: listState, notchHeight: 0, scrolls: false), width: 560), "list-expanded.png")
        return "Rendered to \(directory)"
    }
    #endif

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
