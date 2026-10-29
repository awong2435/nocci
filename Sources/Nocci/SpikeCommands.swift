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
                    case .track(let snapshot): "track (\(snapshot.isPlaying ? "playing" : "paused"))"
                    case .idle: "idle"
                    case .denied: "denied"
                    case .failed(let code): "failed \(code)"
                    }
                    lines.append("\(app.displayName): permission \(permission), poll \(outcome)")
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
