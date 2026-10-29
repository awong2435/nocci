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

    func recent(limit: Int, now: Date) throws -> [NotificationItem] {
        try withDatabase { db in
            try query(db, afterID: -1, deliveredAfter: nil, now: now, limit: limit).map(\.1)
        }
    }

    /// Polls for notifications that arrive, or whose scheduled time passes, after the stream starts.
    public func newItems() -> AsyncStream<NotificationItem> {
        let (stream, continuation) = AsyncStream<NotificationItem>.makeStream()
        let task = Task { await poll(into: continuation) }
        continuation.onTermination = { _ in task.cancel() }
        return stream
    }

    private func poll(into continuation: AsyncStream<NotificationItem>.Continuation) async {
        var lastID: Int64 = (try? withDatabase { db in try maxRecordID(db) }) ?? 0
        var lastCheck = Date()
        while !Task.isCancelled {
            try? await Task.sleep(for: pollInterval)
            let now = Date()
            let fresh: [(Int64, NotificationItem)]
            do {
                fresh = try withDatabase { db in
                    try query(db, afterID: lastID, deliveredAfter: lastCheck, now: now, limit: 100)
                }
            } catch {
                continue
            }
            lastCheck = now
            // Query returns newest first; emit oldest first.
            for (recordID, item) in fresh.reversed() {
                continuation.yield(item)
                lastID = max(lastID, recordID)
            }
        }
        continuation.finish()
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
        recordID: Int64,
        bundleID: String,
        data: Data,
        deliveredDate: Double,
        appName: (String) -> String
    ) -> NotificationItem? {
        guard let plist = plistDictionary(data) else { return nil }
        let req = plist["req"] as? [String: Any] ?? [:]
        return NotificationItem(
            id: String(recordID),
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
    private func query(
        _ db: OpaquePointer,
        afterID: Int64,
        deliveredAfter: Date?,
        now: Date,
        limit: Int
    ) throws -> [(Int64, NotificationItem)] {
        let sql = """
            SELECT r.rec_id, a.identifier, r.data, r.delivered_date
            FROM record r JOIN app a ON a.app_id = r.app_id
            WHERE (r.rec_id > ?1 OR r.delivered_date > ?2) AND r.delivered_date <= ?3
            ORDER BY r.rec_id DESC
            LIMIT ?4
            """
        let statement = try prepare(db, sql)
        defer { sqlite3_finalize(statement) }
        sqlite3_bind_int64(statement, 1, afterID)
        sqlite3_bind_double(statement, 2, deliveredAfter?.timeIntervalSinceReferenceDate ?? .greatestFiniteMagnitude)
        sqlite3_bind_double(statement, 3, now.timeIntervalSinceReferenceDate)
        sqlite3_bind_int64(statement, 4, Int64(limit))

        var rows: [(Int64, NotificationItem)] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            let id = sqlite3_column_int64(statement, 0)
            guard let bundleID = sqlite3_column_text(statement, 1).map({ String(cString: $0) }),
                  let data = columnData(statement, 2),
                  let item = Self.item(
                      recordID: id,
                      bundleID: bundleID,
                      data: data,
                      deliveredDate: sqlite3_column_double(statement, 3),
                      appName: appName
                  )
            else { continue }
            rows.append((id, item))
        }
        return rows
    }

    private func maxRecordID(_ db: OpaquePointer) throws -> Int64 {
        let statement = try prepare(db, "SELECT COALESCE(MAX(rec_id), 0) FROM record")
        defer { sqlite3_finalize(statement) }
        return sqlite3_step(statement) == SQLITE_ROW ? sqlite3_column_int64(statement, 0) : 0
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
            "Notification database not found. Tuck probably doesn't have Full Disk Access yet."
        case .open(let code):
            "Couldn't open the notification database read-only (SQLite code \(code)). Check Full Disk Access."
        case .query(let code, let message):
            "Query failed (SQLite code \(code)): \(message)"
        }
    }
}
