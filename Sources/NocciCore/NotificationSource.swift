import Foundation

/// Where notifications come from. `MockSource` for UI work, `DatabaseSource` (M2) for real data.
public protocol NotificationSource: Sendable {
    /// The most recent notifications, newest first.
    func recent(limit: Int) async throws -> [NotificationItem]

    /// Notifications that arrive after the source starts.
    func newItems() -> AsyncStream<NotificationItem>

    /// IDs of every notification that still exists, to notice ones cleared elsewhere (Notification Center).
    /// Nil when the source can't tell.
    func existingIDs() async throws -> Set<NotificationItem.ID>?
}
