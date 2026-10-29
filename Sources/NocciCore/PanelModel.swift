import Foundation
import Observation

/// Decides what the notch panel shows. The app turns `state` into windows and animation.
@MainActor
@Observable
public final class PanelModel {
    public let store: NotificationStore
    public private(set) var state: PanelState = .hidden
    public var alertDuration: AlertDuration

    @ObservationIgnored private var expiry: Task<Void, Never>?

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
    /// A newer notification replaces the current alert and restarts the timer.
    public func receive(_ item: NotificationItem) {
        let isNew = !store.allItems.contains { $0.id == item.id }
        store.ingest([item])
        // Hidden apps and dismissed notifications don't alert. While the list is open, new ones just appear in it.
        guard isNew, store.isVisible(item), state != .list else { return }
        state = .alert(item.id)
        scheduleExpiry(for: item.id)
    }

    /// Opens the island and, when the notification list is shown in it, marks everything as read.
    public func openList(marksRead: Bool = true, now: Date = Date()) {
        expiry?.cancel()
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
    public func dismiss(id: NotificationItem.ID) {
        store.dismiss(id: id)
        if state == .alert(id) {
            expireAlert(id: id)
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
