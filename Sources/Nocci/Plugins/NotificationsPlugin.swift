import NocciCore
import SwiftUI

/// The notification list as a plugin, so it can be ordered alongside others. Alerts and the unread indicator
/// are core and don't depend on it being turned on.
@MainActor
final class NotificationsPlugin: NocciPlugin {
    let id = "notifications"
    let name = "Notifications"
    let systemImage = "bell"
    let hasContent = true
    let showsCompact = false

    private let store: NotificationStore

    init(store: NotificationStore) {
        self.store = store
    }

    func makeSection() -> AnyView {
        AnyView(NotificationList(store: store, notchHeight: 0, scrolls: false))
    }

    func makeCompactLeading() -> AnyView { AnyView(EmptyView()) }
    func makeCompactTrailing() -> AnyView { AnyView(EmptyView()) }
    func setActive(_ active: Bool) {}
}
