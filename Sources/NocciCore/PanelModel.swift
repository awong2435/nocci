import Foundation
import Observation

/// Decides what the notch panel shows. The app turns `state` into windows and animation.
@MainActor
@Observable
public final class PanelModel {
    public let store: NotificationStore
    public private(set) var state: PanelState = .hidden
    public var alertDuration: AlertDuration
    /// Older notifications that arrived while the current alert was up, newest first (at most two). They show as
    /// a stack behind the alert, like Notification Center, instead of being replaced.
    public private(set) var stackedAlerts: [NotificationItem.ID] = []

    @ObservationIgnored private var expiry: Task<Void, Never>?
    /// Counts notifications received, so a sync can tell one arrived while it was reading (and skip that round).
    @ObservationIgnored public private(set) var receivedCount = 0

    public init(store: NotificationStore, alertDuration: AlertDuration = .tenSeconds) {
        self.store = store
        self.alertDuration = alertDuration
    }

    /// The notification currently shown as an alert, if any.
    public var currentAlert: NotificationItem? {
        guard case .alert(let id) = state else { return nil }
        return store.items.first { $0.id == id }
    }

    /// A notification arrived. Shows it as an alert unless it was already known or dismissed.
    /// If an alert is already up, the new one goes on top and the old one stacks behind it; the timer restarts.
    public func receive(_ item: NotificationItem) {
        let isNew = !store.allItems.contains { $0.id == item.id }
        receivedCount += 1
        store.ingest([item])
        // Hidden apps and dismissed notifications don't alert. While the list is open, new ones just appear in it.
        guard isNew, store.isVisible(item), state != .list else { return }
        if case .alert(let current) = state {
            stackedAlerts = Array(([current] + stackedAlerts).prefix(2))
        } else {
            stackedAlerts = []
        }
        state = .alert(item.id)
        scheduleExpiry(for: item.id)
    }

    /// Opens the island and, when the notification list is shown in it, marks everything as read.
    public func openList(marksRead: Bool = true, now: Date = Date()) {
        expiry?.cancel()
        stackedAlerts = []
        if marksRead { store.markAllRead(now: now) }
        state = .list
    }

    /// Closes the island. Anything that arrived while the list was showing was seen, so it's read too.
    public func closeList(marksRead: Bool = true, now: Date = Date()) {
        guard state == .list else { return }
        if marksRead { store.markAllRead(now: now) }
        state = restingState
    }

    /// Ends the alert for `id`, if it's still the one showing, and collapses to the counter.
    public func expireAlert(id: NotificationItem.ID) {
        guard state == .alert(id) else { return }
        expiry?.cancel()
        stackedAlerts = []
        state = restingState
    }

    /// Re-evaluates the counter after the store changes outside an alert, such as the first load at launch.
    public func refresh() {
        guard state == .hidden || state == .counter else { return }
        state = restingState
    }

    /// Counter when anything is unread, otherwise hidden.
    private var restingState: PanelState {
        store.unreadCount > 0 ? .counter : .hidden
    }

    /// Dismisses a notification: it leaves the list and stops counting as unread. If it's the alert showing,
    /// the alert collapses.
    /// Dismissing the top of a stack brings up the next one in it.
    public func dismiss(id: NotificationItem.ID) {
        store.dismiss(id: id)
        stackedAlerts.removeAll { $0 == id }
        if state == .alert(id) {
            if stackedAlerts.isEmpty {
                expireAlert(id: id)
            } else {
                let next = stackedAlerts.removeFirst()
                state = .alert(next)
                scheduleExpiry(for: next)
            }
        }
    }

    /// Drops notifications cleared in macOS's Notification Center. If the alert showing was one of them, the next
    /// one in its stack comes up, or the alert collapses.
    public func removeMissing(keeping existing: Set<NotificationItem.ID>) {
        store.removeMissing(keeping: existing)
        stackedAlerts.removeAll { !existing.contains($0) }
        guard case .alert(let id) = state, !existing.contains(id) else {
            if state == .counter, store.unreadCount == 0 { state = .hidden }
            return
        }
        if stackedAlerts.isEmpty {
            expireAlert(id: id)
        } else {
            let next = stackedAlerts.removeFirst()
            state = .alert(next)
            scheduleExpiry(for: next)
        }
    }

    /// Hides the current alert now, without dismissing the notification.
    public func dismissAlert() {
        guard case .alert(let id) = state else { return }
        expireAlert(id: id)
    }

    private func scheduleExpiry(for id: NotificationItem.ID) {
        expiry?.cancel()
        guard let seconds = alertDuration.seconds else { return }
        expiry = Task { [weak self] in
            try? await Task.sleep(for: .seconds(seconds))
            guard !Task.isCancelled else { return }
            self?.expireAlert(id: id)
        }
    }
}
