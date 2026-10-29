import AppKit
import NocciCore

/// M2 spike: one-shot commands that print to stdout and exit instead of showing the panel.
///
/// Run through `open` so macOS attributes Full Disk Access to Nocci rather than to the terminal:
///   open -n -W --stdout "$(tty)" --stderr "$(tty)" build/Nocci.app --args --db-info
///   open -n -W --stdout "$(tty)" --stderr "$(tty)" build/Nocci.app --args --db-dates
///   open -n -W --stdout "$(tty)" --stderr "$(tty)" build/Nocci.app --args --print-recent 10
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
        if let index = arguments.firstIndex(of: "--print-recent") {
            let limit = arguments.dropFirst(index + 1).first.flatMap(Int.init) ?? 10
            run {
                try source().recent(limit: limit, now: Date()).map(format).joined(separator: "\n\n")
            }
            return true
        }
        return false
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
