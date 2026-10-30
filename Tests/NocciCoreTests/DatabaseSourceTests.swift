import Foundation
import SQLite3
import Testing
@testable import NocciCore

/// Runs against a small fake database with the same layout, never the real one.
struct DatabaseSourceTests {
    let url: URL

    init() throws {
        url = FileManager.default.temporaryDirectory.appending(path: "nocci-fixture-\(UUID().uuidString).db")
        var db: OpaquePointer?
        #expect(sqlite3_open(url.path, &db) == SQLITE_OK)
        defer { sqlite3_close(db) }
        // WAL mode, like the real database, so readers and the writer never block each other.
        sqlite3_exec(db, """
            PRAGMA journal_mode = WAL;
            CREATE TABLE app (app_id INTEGER PRIMARY KEY, identifier VARCHAR);
            CREATE TABLE record (rec_id INTEGER PRIMARY KEY, app_id INTEGER, data BLOB, delivered_date REAL, uuid BLOB);
            INSERT INTO app VALUES (1, 'com.tinyspeck.slackmacgap'), (2, 'com.apple.mail');
            """, nil, nil, nil)
        try Self.insert(db, recordID: 1, appID: 1, date: 100, req: ["titl": "Oldest", "body": "first"])
        // Arrived early but scheduled for tomorrow, like a Calendar reminder.
        try Self.insert(db, recordID: 2, appID: 2, date: Self.tomorrow, req: ["titl": "Scheduled", "body": "later"])
        try Self.insert(db, recordID: 3, appID: 2, date: 300, req: ["titl": "Middle", "subt": "Inbox", "body": "second"])
        // Arrived last even though its delivered date is earlier.
        try Self.insert(db, recordID: 4, appID: 1, date: 200, req: ["titl": "Newest", "subt": "", "body": "third"])
    }

    static let tomorrow = Date().timeIntervalSinceReferenceDate + 86_400

    static func insert(_ db: OpaquePointer?, recordID: Int64, appID: Int64, date: Double, req: [String: String]) throws {
        let data = try PropertyListSerialization.data(fromPropertyList: ["req": req, "app": "x"], format: .binary, options: 0)
        var statement: OpaquePointer?
        sqlite3_prepare_v2(db, "INSERT INTO record VALUES (?, ?, ?, ?, ?)", -1, &statement, nil)
        defer { sqlite3_finalize(statement) }
        sqlite3_bind_int64(statement, 1, recordID)
        sqlite3_bind_int64(statement, 2, appID)
        _ = data.withUnsafeBytes { sqlite3_bind_blob(statement, 3, $0.baseAddress, Int32(data.count), nil) }
        sqlite3_bind_double(statement, 4, date)
        // A fresh unique ID per insert, like macOS's (it never reuses them, unlike rec_id).
        let uuid = withUnsafeBytes(of: UUID().uuid) { Data($0) }
        _ = uuid.withUnsafeBytes { sqlite3_bind_blob(statement, 5, $0.baseAddress, Int32(uuid.count), unsafeBitCast(-1, to: sqlite3_destructor_type.self)) }
        #expect(sqlite3_step(statement) == SQLITE_DONE)
    }

    @Test func recentIsInArrivalOrderWithParsedFields() async throws {
        let source = DatabaseSource(url: url, appName: { $0 == "com.apple.mail" ? "Mail" : "Slack" })
        let items = try await source.recent(limit: 2)

        #expect(items.map(\.title) == ["Newest", "Middle"])
        #expect(items[0].subtitle == nil)
        #expect(items[0].body == "third")
        #expect(items[1].appName == "Mail")
        #expect(items[1].subtitle == "Inbox")
        #expect(items[1].date == Date(timeIntervalSinceReferenceDate: 300))
    }

    @Test func scheduledItemsAppearOnlyOnceDue() throws {
        let source = DatabaseSource(url: url)
        #expect(try source.recent(limit: 10, now: Date()).map(\.title) == ["Newest", "Middle", "Oldest"])

        let dayAfter = Date(timeIntervalSinceReferenceDate: Self.tomorrow + 86_400)
        #expect(try source.recent(limit: 10, now: dayAfter).map(\.title) == ["Newest", "Middle", "Scheduled", "Oldest"])
    }

    @Test func schemaDescriptionHasStructureButNoText() throws {
        let description = try DatabaseSource(url: url).describeSchema()
        #expect(description.contains("table record (4 rows)"))
        #expect(description.contains("plist req keys: body, subt, titl"))
        #expect(!description.contains("Newest"))
        #expect(!description.contains("third"))
    }

    @Test func databaseIsOpenedReadOnly() throws {
        let before = try Data(contentsOf: url)
        _ = try DatabaseSource(url: url).describeSchema()
        #expect(try Data(contentsOf: url) == before)
    }

    @Test func missingDatabaseThrows() async {
        let source = DatabaseSource(url: URL(filePath: "/nonexistent/db"))
        await #expect(throws: DatabaseError.self) { try await source.recent(limit: 1) }
    }
}

extension DatabaseSourceTests {
    @Test(.timeLimit(.minutes(1)))
    func newItemsEmitsRecordsAddedAfterStart() async throws {
        let source = DatabaseSource(url: url, pollInterval: .milliseconds(100))
        var iterator = source.newItems().makeAsyncIterator()

        try await Task.sleep(for: .milliseconds(250))
        var db: OpaquePointer?
        sqlite3_open(url.path, &db)
        sqlite3_busy_timeout(db, 5_000)
        try Self.insert(db, recordID: 5, appID: 1, date: Date().timeIntervalSinceReferenceDate - 1, req: ["titl": "Live"])
        sqlite3_close(db)

        let first = await iterator.next()
        #expect(first?.title == "Live")
    }
}

extension DatabaseSourceTests {
    /// macOS reuses rec_id after the newest record is deleted, and writes seconds after delivery; a new
    /// notification on a reused rec_id, with a delivered date already in the past, must still come through.
    @Test(.timeLimit(.minutes(1)))
    func newItemsCatchesANotificationOnAReusedRecordNumber() async throws {
        var db: OpaquePointer?
        sqlite3_open(url.path, &db)
        sqlite3_busy_timeout(db, 5_000)
        try Self.insert(db, recordID: 5, appID: 1, date: Date().timeIntervalSinceReferenceDate - 60, req: ["titl": "Cleared later"])

        let source = DatabaseSource(url: url, pollInterval: .milliseconds(100))
        var iterator = source.newItems().makeAsyncIterator()

        try await Task.sleep(for: .milliseconds(250))
        sqlite3_exec(db, "DELETE FROM record WHERE rec_id = 5", nil, nil, nil)
        try Self.insert(db, recordID: 5, appID: 1, date: Date().timeIntervalSinceReferenceDate - 8, req: ["titl": "Reused"])
        sqlite3_close(db)

        let next = await iterator.next()
        #expect(next?.title == "Reused")
    }
}

extension DatabaseSourceTests {
    @Test func clickLinkPrefersTheAppsOwnLink() {
        let url = DatabaseSource.actionURL(bundleID: "com.apple.iCal", req: ["durl": "ical://ekevent/ABC"])
        #expect(url?.absoluteString == "ical://ekevent/ABC")
    }

    @Test func slackClickLinkIsBuiltFromTheNotificationID() {
        let url = DatabaseSource.actionURL(bundleID: "com.tinyspeck.slackmacgap", req: ["iden": "C012AB3CD_1761234567.123456"])
        #expect(url?.absoluteString == "slack://channel?id=C012AB3CD&message=1761234567.123456")
    }

    @Test func noClickLinkWhenTheIDIsUnexpected() {
        #expect(DatabaseSource.actionURL(bundleID: "com.tinyspeck.slackmacgap", req: ["iden": "something else"]) == nil)
        #expect(DatabaseSource.actionURL(bundleID: "com.example.app", req: [:]) == nil)
    }
}
