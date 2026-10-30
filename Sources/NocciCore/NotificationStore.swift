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

    /// Bundle IDs of apps whose notifications are hidden. Hidden items stay in `allItems`.
    public var hiddenApps: Set<String> = []

    /// Whether an item should be shown: not dismissed, and its app isn't hidden.
    public func isVisible(_ item: NotificationItem) -> Bool {
        !dismissedIDs.contains(item.id) && !hiddenApps.contains(item.appBundleID)
    }

    /// Visible notifications, newest first.
    public var items: [NotificationItem] {
        allItems.filter(isVisible)
    }

    /// Every app that appears in `allItems` (hidden or not), once each, sorted by name.
    public var knownApps: [(bundleID: String, name: String)] {
        var seen: Set<String> = []
        var apps: [(bundleID: String, name: String)] = []
        for item in allItems where seen.insert(item.appBundleID).inserted {
            apps.append((bundleID: item.appBundleID, name: item.appName))
        }
        return apps.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    /// Visible notifications grouped by app. Groups are ordered by their newest notification,
    /// and each group's notifications are newest first.
    public var groupedByApp: [AppGroup] {
        var groups: [AppGroup] = []
        var index: [String: Int] = [:]
        for item in items {
            if let i = index[item.appBundleID] {
                groups[i].items.append(item)
            } else {
                index[item.appBundleID] = groups.count
                groups.append(AppGroup(appBundleID: item.appBundleID, appName: item.appName, items: [item]))
            }
        }
        return groups
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

    /// Drops notifications that no longer exist in macOS (cleared in Notification Center), so the list matches
    /// it. `existing` is every ID macOS still has.
    public func removeMissing(keeping existing: Set<NotificationItem.ID>) {
        guard allItems.contains(where: { !existing.contains($0.id) }) else { return }
        allItems.removeAll { !existing.contains($0.id) }
        dismissedIDs.formIntersection(existing)
    }
}

/// One app's notifications in the list.
public struct AppGroup: Identifiable, Sendable {
    public var id: String { appBundleID }
    public let appBundleID: String
    public let appName: String
    public var items: [NotificationItem]
}
