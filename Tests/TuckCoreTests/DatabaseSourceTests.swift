import Foundation
import SQLite3
import Testing
@testable import TuckCore

/// Runs against a small fake database with the same layout, never the real one.
struct DatabaseSourceTests {
    let url: URL

    init() throws {
        url = FileManager.default.temporaryDirectory.appending(path: "tuck-fixture-\(UUID().uuidString).db")
        var db: OpaquePointer?
        #expect(sqlite3_open(url.path, &db) == SQLITE_OK)
        defer { sqlite3_close(db) }
        sqlite3_exec(db, """
            CREATE TABLE app (app_id INTEGER PRIMARY KEY, identifier VARCHAR);
            CREATE TABLE record (rec_id INTEGER PRIMARY KEY, app_id INTEGER, data BLOB, delivered_date REAL);
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
        sqlite3_prepare_v2(db, "INSERT INTO record VALUES (?, ?, ?, ?)", -1, &statement, nil)
        defer { sqlite3_finalize(statement) }
        sqlite3_bind_int64(statement, 1, recordID)
        sqlite3_bind_int64(statement, 2, appID)
        _ = data.withUnsafeBytes { sqlite3_bind_blob(statement, 3, $0.baseAddress, Int32(data.count), nil) }
        sqlite3_bind_double(statement, 4, date)
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
    @Test func newItemsEmitsRecordsAddedAfterStart() async throws {
        let source = DatabaseSource(url: url, pollInterval: .milliseconds(100))
        let stream = source.newItems()
        let fixture = url
        Task.detached {
            try await Task.sleep(for: .milliseconds(300))
            var db: OpaquePointer?
            sqlite3_open(fixture.path, &db)
            defer { sqlite3_close(db) }
            try Self.insert(db, recordID: 5, appID: 1, date: Date().timeIntervalSinceReferenceDate - 1, req: ["titl": "Live"])
        }
        var iterator = stream.makeAsyncIterator()
        let first = await iterator.next()
        #expect(first?.title == "Live")
    }
}
