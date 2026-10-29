import AppKit
import TuckCore

/// M2 spike: one-shot commands that print to stdout and exit instead of showing the panel.
///
/// Run through `open` so macOS attributes Full Disk Access to Tuck rather than to the terminal:
///   open -n -W --stdout "$(tty)" --stderr "$(tty)" build/Tuck.app --args --db-info
///   open -n -W --stdout "$(tty)" --stderr "$(tty)" build/Tuck.app --args --db-dates
///   open -n -W --stdout "$(tty)" --stderr "$(tty)" build/Tuck.app --args --print-recent 10
enum SpikeCommands {
    /// Runs a spike command if one was passed. Returns `false` to continue launching the app normally.
    static func runIfRequested(_ arguments: [String]) async -> Bool {
        if arguments.contains("--db-info") {
            run { try source().describeSchema() }
            return true
        }
        if arguments.contains("--db-dates") {
            run { try source().describeDates() }
            return true
        }
        if let index = arguments.firstIndex(of: "--print-recent") {
            let limit = arguments.dropFirst(index + 1).first.flatMap(Int.init) ?? 10
            await runAsync {
                let items = try await source().recent(limit: limit)
                return items.map(format).joined(separator: "\n\n")
            }
            return true
        }
        return false
    }

    static func appName(for bundleID: String) -> String {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else { return bundleID }
        return FileManager.default.displayName(atPath: url.path).replacingOccurrences(of: ".app", with: "")
    }

    private static func source() throws -> DatabaseSource {
        guard let url = DatabaseSource.locate() else { throw DatabaseError.notFound }
        return DatabaseSource(url: url, appName: appName(for:))
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

    private static func runAsync(_ body: () async throws -> String) async {
        do { print(try await body()) } catch { printError(error) }
    }

    private static func printError(_ error: Error) {
        FileHandle.standardError.write(Data("error: \(error)\n".utf8))
    }
}
