import Foundation
import Observation

/// Holds notifications in memory and applies the unread and dismiss rules.
///
/// Unread means: arrived after `lastOpened` and not dismissed.
/// Only `lastOpened` and `dismissedIDs` may ever be persisted (M4), never message text.
@MainActor
@Observable
public final class NotificationStore {
    /// All known notifications, newest first, including dismissed ones.
    public private(set) var allItems: [NotificationItem] = []
    public private(set) var dismissedIDs: Set<NotificationItem.ID>
    public private(set) var lastOpened: Date?

    public init(lastOpened: Date? = nil, dismissedIDs: Set<NotificationItem.ID> = []) {
        self.lastOpened = lastOpened
        self.dismissedIDs = dismissedIDs
    }

    /// Visible notifications, newest first.
    public var items: [NotificationItem] {
        allItems.filter { !dismissedIDs.contains($0.id) }
    }

    public var unreadCount: Int {
        items.filter { item in lastOpened.map { item.date > $0 } ?? true }.count
    }

    /// Adds notifications, ignoring IDs already known.
    public func ingest(_ newItems: [NotificationItem]) {
        let known = Set(allItems.map(\.id))
        let fresh = newItems.filter { !known.contains($0.id) }
        guard !fresh.isEmpty else { return }
        allItems = (allItems + fresh).sorted { $0.date > $1.date }
    }

    /// Opening the list marks everything as read.
    public func markAllRead(now: Date = Date()) {
        lastOpened = now
    }

    public func dismiss(id: NotificationItem.ID) {
        dismissedIDs.insert(id)
    }
}
