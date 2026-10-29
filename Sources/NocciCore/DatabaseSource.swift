import Foundation
import SQLite3

/// Reads macOS's own notification database, strictly read-only.
///
/// Requires Full Disk Access. Never writes to or copies the database, and keeps results in memory only.
/// Layout (per the Plaso parser): `app(app_id, identifier)` and `record(rec_id, app_id, data, delivered_date)`,
/// where `data` is a binary plist whose `req` dictionary holds `titl`, `subt`, and `body`.
public struct DatabaseSource: NotificationSource {
    public let url: URL
    /// Turns a bundle ID into a display name. The app supplies one backed by NSWorkspace.
    public let appName: @Sendable (String) -> String
    public let pollInterval: Duration

    public init(
        url: URL,
        pollInterval: Duration = .seconds(2),
        appName: @escaping @Sendable (String) -> String = { $0 }
    ) {
        self.url = url
        self.pollInterval = pollInterval
        self.appName = appName
    }

    /// Where the database lives on this Mac, checked in order. macOS 15+ first, then the older location.
    public static func candidateURLs() -> [URL] {
        var urls = [
            FileManager.default.homeDirectoryForCurrentUser
                .appending(path: "Library/Group Containers/group.com.apple.usernoted/db2/db"),
        ]
        if let userDir = darwinUserDir() {
            urls.append(URL(filePath: userDir).appending(path: "com.apple.notificationcenter/db2/db"))
        }
        return urls
    }

    /// The first candidate that exists, or `nil`. Without Full Disk Access the macOS 15+ path can't even be seen.
    public static func locate() -> URL? {
        candidateURLs().first { FileManager.default.fileExists(atPath: $0.path) }
    }

    /// The most recently arrived notifications, skipping any scheduled for later (such as Calendar reminders).
    public func recent(limit: Int) async throws -> [NotificationItem] {
        try recent(limit: limit, now: Date())
    }

    /// Synchronous version of `recent(limit:)`, for command-line use and tests.
    public func recent(limit: Int, now: Date) throws -> [NotificationItem] {
        try withDatabase { db in
            try query(db, newest: limit, dueSince: nil, now: now)
        }
    }

    /// Polls for notifications that arrive, or whose scheduled time passes, after the stream starts.
    ///
    /// Record numbers can't be used to spot new ones: macOS reuses them after notifications are cleared, and
    /// writes in batches seconds after delivery. So each poll reads the newest records (plus anything that
    /// became due recently) and emits the ones whose unique ID hasn't been seen.
    public func newItems() -> AsyncStream<NotificationItem> {
        // Take the starting point now, not when the task first runs, so nothing that arrives
        // in between is skipped.
        let seen = Set(((try? withDatabase { db in try window(db, now: Date()) }) ?? []).map(\.id))
        let (stream, continuation) = AsyncStream<NotificationItem>.makeStream()
        let task = Task { await poll(into: continuation, seen: seen) }
        continuation.onTermination = { _ in task.cancel() }
        return stream
    }

    private func poll(into continuation: AsyncStream<NotificationItem>.Continuation, seen startingSeen: Set<String>) async {
        var seen = startingSeen
        while !Task.isCancelled {
            try? await Task.sleep(for: pollInterval)
            guard let items = try? withDatabase({ db in try window(db, now: Date()) }) else { continue }
            // Newest first from the query; emit oldest first.
            for item in items.reversed() where !seen.contains(item.id) {
                seen.insert(item.id)
                continuation.yield(item)
            }
        }
        continuation.finish()
    }

    /// The records a poll looks at: the 100 newest, plus scheduled ones that came due in the last 5 minutes.
    private func window(_ db: OpaquePointer, now: Date) throws -> [NotificationItem] {
        try query(db, newest: 100, dueSince: now.addingTimeInterval(-300), now: now)
    }

    /// Table names, column names, and the plist keys seen in recent records.
    /// Structure only: no titles, bodies, or other message text.
    public func describeSchema(sampleSize: Int = 20) throws -> String {
        try withDatabase { db in
            var lines = ["path: \(url.path)"]
            for table in try strings(db, "SELECT name FROM sqlite_master WHERE type = 'table' ORDER BY name") {
                let columns = try strings(db, "SELECT name FROM pragma_table_info('\(table)')")
                let count = try strings(db, "SELECT COUNT(*) FROM \"\(table)\"").first ?? "?"
                lines.append("table \(table) (\(count) rows): \(columns.joined(separator: ", "))")
            }
            var topKeys = Set<String>(), reqKeys = Set<String>()
            for blob in try blobs(db, "SELECT data FROM record ORDER BY rec_id DESC LIMIT \(sampleSize)") {
                guard let plist = Self.plistDictionary(blob) else { continue }
                topKeys.formUnion(plist.keys)
                if let req = plist["req"] as? [String: Any] { reqKeys.formUnion(req.keys) }
            }
            lines.append("plist keys: \(topKeys.sorted().joined(separator: ", "))")
            lines.append("plist req keys: \(reqKeys.sorted().joined(separator: ", "))")
            return lines.joined(separator: "\n")
        }
    }

    /// Record IDs, bundle IDs, and timestamps for the newest records, by arrival and by delivered date.
    /// Metadata only: no titles, bodies, or other message text.
    public func describeDates(limit: Int = 15) throws -> String {
        try withDatabase { db in
            let columns = """
                r.rec_id, a.identifier, r.presented, r.style,
                datetime(r.request_date + 978307200, 'unixepoch', 'localtime'),
                datetime(r.request_last_date + 978307200, 'unixepoch', 'localtime'),
                datetime(r.delivered_date + 978307200, 'unixepoch', 'localtime')
                """
            var lines = ["now: \(Date().formatted(date: .numeric, time: .standard))",
                         "rec_id | app | presented | style | request_date | request_last_date | delivered_date"]
            for order in ["r.rec_id", "r.delivered_date"] {
                lines.append("-- newest by \(order)")
                let statement = try prepare(db, "SELECT \(columns) FROM record r JOIN app a ON a.app_id = r.app_id ORDER BY \(order) DESC LIMIT \(limit)")
                defer { sqlite3_finalize(statement) }
                while sqlite3_step(statement) == SQLITE_ROW {
                    let fields = (0..<7).map { i in
                        sqlite3_column_text(statement, Int32(i)).map { String(cString: $0) } ?? "null"
                    }
                    lines.append(fields.joined(separator: " | "))
                }
            }
            return lines.joined(separator: "\n")
        }
    }

    // MARK: - Parsing

    /// Builds an item from one `record` row. Returns `nil` if the plist is unreadable.
    static func item(
        id: String,
        bundleID: String,
        data: Data,
        deliveredDate: Double,
        appName: (String) -> String
    ) -> NotificationItem? {
        guard let plist = plistDictionary(data) else { return nil }
        let req = plist["req"] as? [String: Any] ?? [:]
        return NotificationItem(
            id: id,
            appBundleID: bundleID,
            appName: appName(bundleID),
            title: req["titl"] as? String ?? "",
            subtitle: (req["subt"] as? String).flatMap { $0.isEmpty ? nil : $0 },
            body: req["body"] as? String ?? "",
            // Core Data timestamp: seconds since 2001-01-01.
            date: Date(timeIntervalSinceReferenceDate: deliveredDate)
        )
    }

    static func plistDictionary(_ data: Data) -> [String: Any]? {
        try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any]
    }

    // MARK: - SQLite

    /// Records newer than `afterID`, or whose scheduled time passed after `deliveredAfter`, newest arrival first.
    /// `delivered_date` is the scheduled time for some apps (Calendar), so it can't be used for ordering,
    /// and anything still in the future hasn't been delivered yet.
    /// The `newest` most recently written records, plus any whose scheduled time fell after `dueSince`, newest
    /// arrival first. `delivered_date` is the scheduled time for some apps (Calendar), so it can't be used for
    /// ordering, and anything still in the future hasn't been delivered yet.
    private func query(_ db: OpaquePointer, newest: Int, dueSince: Date?, now: Date) throws -> [NotificationItem] {
        let sql = """
            SELECT r.rec_id, a.identifier, r.data, r.delivered_date, r.uuid
            FROM record r JOIN app a ON a.app_id = r.app_id
            WHERE r.delivered_date <= ?1
              AND (r.rec_id IN (SELECT rec_id FROM record ORDER BY rec_id DESC LIMIT ?2) OR r.delivered_date > ?3)
            ORDER BY r.rec_id DESC
            """
        let statement = try prepare(db, sql)
        defer { sqlite3_finalize(statement) }
        sqlite3_bind_double(statement, 1, now.timeIntervalSinceReferenceDate)
        sqlite3_bind_int64(statement, 2, Int64(newest))
        sqlite3_bind_double(statement, 3, dueSince?.timeIntervalSinceReferenceDate ?? .greatestFiniteMagnitude)

        var items: [NotificationItem] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            let recordID = sqlite3_column_int64(statement, 0)
            guard let bundleID = sqlite3_column_text(statement, 1).map({ String(cString: $0) }),
                  let data = columnData(statement, 2),
                  let item = Self.item(
                      id: columnData(statement, 4).map(Self.hex) ?? "rec-\(recordID)",
                      bundleID: bundleID,
                      data: data,
                      deliveredDate: sqlite3_column_double(statement, 3),
                      appName: appName
                  )
            else { continue }
            items.append(item)
        }
        return items
    }

    /// The record's unique ID as lowercase hex. Unlike `rec_id`, macOS never reuses it.
    static func hex(_ data: Data) -> String {
        data.map { String(format: "%02x", $0) }.joined()
    }

    /// Opens the database read-only for the duration of `body`.
    private func withDatabase<T>(_ body: (OpaquePointer) throws -> T) throws -> T {
        var db: OpaquePointer?
        let uri = "file:\(url.path.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? url.path)?mode=ro"
        let status = sqlite3_open_v2(uri, &db, SQLITE_OPEN_READONLY | SQLITE_OPEN_URI, nil)
        defer { sqlite3_close_v2(db) }
        guard status == SQLITE_OK, let db else {
            throw DatabaseError.open(code: status)
        }
        sqlite3_busy_timeout(db, 500)
        return try body(db)
    }

    private func prepare(_ db: OpaquePointer, _ sql: String) throws -> OpaquePointer {
        var statement: OpaquePointer?
        let status = sqlite3_prepare_v2(db, sql, -1, &statement, nil)
        guard status == SQLITE_OK, let statement else {
            throw DatabaseError.query(code: status, message: String(cString: sqlite3_errmsg(db)))
        }
        return statement
    }

    private func strings(_ db: OpaquePointer, _ sql: String) throws -> [String] {
        let statement = try prepare(db, sql)
        defer { sqlite3_finalize(statement) }
        var result: [String] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            result.append(sqlite3_column_text(statement, 0).map { String(cString: $0) } ?? "")
        }
        return result
    }

    private func blobs(_ db: OpaquePointer, _ sql: String) throws -> [Data] {
        let statement = try prepare(db, sql)
        defer { sqlite3_finalize(statement) }
        var result: [Data] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            if let data = columnData(statement, 0) { result.append(data) }
        }
        return result
    }

    private func columnData(_ statement: OpaquePointer, _ column: Int32) -> Data? {
        guard let bytes = sqlite3_column_blob(statement, column) else { return nil }
        return Data(bytes: bytes, count: Int(sqlite3_column_bytes(statement, column)))
    }

    private static func darwinUserDir() -> String? {
        var buffer = [CChar](repeating: 0, count: Int(PATH_MAX))
        guard confstr(_CS_DARWIN_USER_DIR, &buffer, buffer.count) > 0 else { return nil }
        return String(decoding: buffer.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }, as: UTF8.self)
    }
}

public enum DatabaseError: Error, CustomStringConvertible {
    case notFound
    case open(code: Int32)
    case query(code: Int32, message: String)

    public var description: String {
        switch self {
        case .notFound:
            "Notification database not found. Nocci probably doesn't have Full Disk Access yet."
        case .open(let code):
            "Couldn't open the notification database read-only (SQLite code \(code)). Check Full Disk Access."
        case .query(let code, let message):
            "Query failed (SQLite code \(code)): \(message)"
        }
    }
}
