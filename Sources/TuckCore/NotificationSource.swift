import Foundation

/// Where notifications come from. `MockSource` for UI work, `DatabaseSource` (M2) for real data.
public protocol NotificationSource: Sendable {
    /// The most recent notifications, newest first.
    func recent(limit: Int) async throws -> [NotificationItem]

    /// Notifications that arrive after the source starts.
    func newItems() -> AsyncStream<NotificationItem>
}
