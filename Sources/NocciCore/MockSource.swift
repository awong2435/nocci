import Foundation

/// Fake notifications so the UI can be built without the real database.
public struct MockSource: NotificationSource {
    /// How often `newItems()` emits a fake notification. `nil` emits nothing.
    public let interval: Duration?

    public init(interval: Duration? = nil) {
        self.interval = interval
    }

    public func recent(limit: Int) async throws -> [NotificationItem] {
        Array(Self.samples(now: Date()).prefix(limit))
    }

    /// Fake notifications are never cleared elsewhere.
    public func existingIDs() async throws -> Set<NotificationItem.ID>? { nil }

    public func newItems() -> AsyncStream<NotificationItem> {
        guard let interval else { return AsyncStream { $0.finish() } }
        return AsyncStream { continuation in
            let task = Task {
                var n = 0
                while !Task.isCancelled {
                    try? await Task.sleep(for: interval)
                    if Task.isCancelled { break }
                    n += 1
                    continuation.yield(NotificationItem(
                        id: "mock-live-\(n)",
                        appBundleID: "com.tinyspeck.slackmacgap",
                        appName: "Slack",
                        title: "Mock message \(n)",
                        body: "This is fake notification number \(n) from MockSource.",
                        date: Date()
                    ))
                }
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    static func samples(now: Date) -> [NotificationItem] {
        [
            NotificationItem(
                id: "mock-1", appBundleID: "com.tinyspeck.slackmacgap", appName: "Slack",
                title: "Jordan", subtitle: "#support",
                body: "Can you take a look at the queue when you get a sec?",
                date: now.addingTimeInterval(-60)
            ),
            NotificationItem(
                id: "mock-2", appBundleID: "com.apple.mail", appName: "Mail",
                title: "Weekly report", body: "Your weekly summary is ready.",
                date: now.addingTimeInterval(-15 * 60)
            ),
            NotificationItem(
                id: "mock-3", appBundleID: "com.apple.iCal", appName: "Calendar",
                title: "Standup", body: "Starts in 10 minutes.",
                date: now.addingTimeInterval(-2 * 60 * 60)
            ),
        ]
    }
}
