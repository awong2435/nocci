import Foundation
import Testing
@testable import TuckCore

@MainActor
struct PanelModelTests {
    func item(_ id: String) -> NotificationItem {
        NotificationItem(id: id, appBundleID: "app", appName: "App", title: id, body: "", date: Date())
    }

    func model() -> PanelModel {
        PanelModel(store: NotificationStore(), alertDuration: .untilDismissed)
    }

    @Test func newNotificationShowsAnAlert() {
        let model = model()
        model.receive(item("a"))
        #expect(model.state == .alert("a"))
        #expect(model.currentAlert?.id == "a")
    }

    @Test func knownNotificationDoesNotAlert() {
        let model = model()
        model.store.ingest([item("a")])
        model.receive(item("a"))
        #expect(model.state == .hidden)
    }

    @Test func dismissedNotificationDoesNotAlert() {
        let model = PanelModel(store: NotificationStore(dismissedIDs: ["a"]), alertDuration: .untilDismissed)
        model.receive(item("a"))
        #expect(model.state == .hidden)
    }

    @Test func newerNotificationReplacesTheAlert() {
        let model = model()
        model.receive(item("a"))
        model.receive(item("b"))
        #expect(model.state == .alert("b"))
    }

    @Test func staleExpiryLeavesTheNewerAlert() {
        let model = model()
        model.receive(item("a"))
        model.receive(item("b"))
        model.expireAlert(id: "a")
        #expect(model.state == .alert("b"))
        model.expireAlert(id: "b")
        #expect(model.state == .counter)
    }

    @Test func expiredAlertCollapsesToTheCounter() {
        let model = model()
        model.receive(item("a"))
        model.receive(item("b"))
        model.dismissAlert()
        #expect(model.state == .counter)
        #expect(model.store.unreadCount == 2)
    }

    @Test func expiredAlertHidesWhenNothingIsUnread() {
        // Opened after the notification arrived, so it's already read.
        let model = PanelModel(store: NotificationStore(lastOpened: .distantFuture), alertDuration: .untilDismissed)
        model.receive(item("a"))
        model.dismissAlert()
        #expect(model.state == .hidden)
    }

    @Test func refreshShowsTheCounterForUnreadLoadedAtLaunch() {
        let model = model()
        model.store.ingest([item("a")])
        #expect(model.state == .hidden)
        model.refresh()
        #expect(model.state == .counter)
    }

    @Test func refreshLeavesAnAlertAlone() {
        let model = model()
        model.receive(item("a"))
        model.refresh()
        #expect(model.state == .alert("a"))
    }

    @Test func dismissHidesTheAlertButKeepsTheNotification() {
        let model = model()
        model.receive(item("a"))
        model.dismissAlert()
        #expect(model.state == .counter)
        #expect(model.store.items.map(\.id) == ["a"])
    }

    @Test func alertExpiresAfterItsDuration() async throws {
        let model = PanelModel(store: NotificationStore(), alertDuration: .fiveSeconds)
        model.receive(item("a"))
        #expect(model.state == .alert("a"))
        // Allow slack for a busy main actor while other tests run in parallel.
        for _ in 0..<40 where model.state != .counter {
            try await Task.sleep(for: .milliseconds(250))
        }
        #expect(model.state == .counter)
    }
}
