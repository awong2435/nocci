import Foundation
import Testing
@testable import NocciCore

@MainActor
struct NotificationStoreTests {
    let t0 = Date(timeIntervalSince1970: 1_000_000)

    func item(_ id: String, at offset: TimeInterval) -> NotificationItem {
        NotificationItem(id: id, appBundleID: "app", appName: "App", title: id, body: "", date: t0.addingTimeInterval(offset))
    }

    @Test func everythingIsUnreadBeforeFirstOpen() {
        let store = NotificationStore()
        store.ingest([item("a", at: 0), item("b", at: 10)])
        #expect(store.unreadCount == 2)
    }

    @Test func itemsAreNewestFirstAndDeduplicated() {
        let store = NotificationStore()
        store.ingest([item("a", at: 0), item("b", at: 10)])
        store.ingest([item("b", at: 10), item("c", at: 5)])
        #expect(store.items.map(\.id) == ["b", "c", "a"])
    }

    @Test func openingTheListClearsUnread() {
        let store = NotificationStore()
        store.ingest([item("a", at: 0)])
        store.markAllRead(now: t0.addingTimeInterval(1))
        #expect(store.unreadCount == 0)

        store.ingest([item("b", at: 2)])
        #expect(store.unreadCount == 1)
    }

    @Test func dismissedItemsLeaveTheListAndDontCount() {
        let store = NotificationStore()
        store.ingest([item("a", at: 0), item("b", at: 10)])
        store.dismiss(id: "a")
        #expect(store.items.map(\.id) == ["b"])
        #expect(store.unreadCount == 1)
    }

    @Test func dismissedIDsSurviveReingest() {
        let store = NotificationStore(dismissedIDs: ["a"])
        store.ingest([item("a", at: 0)])
        #expect(store.items.isEmpty)
        #expect(store.unreadCount == 0)
    }
}

extension NotificationStoreTests {
    @Test func groupsByAppNewestFirst() {
        let store = NotificationStore()
        func item(_ id: String, _ app: String, at offset: TimeInterval) -> NotificationItem {
            NotificationItem(id: id, appBundleID: app, appName: app, title: id, body: "", date: t0.addingTimeInterval(offset))
        }
        store.ingest([item("s1", "slack", at: 0), item("m1", "mail", at: 10), item("s2", "slack", at: 20), item("m2", "mail", at: 5)])
        store.dismiss(id: "m2")
        let groups = store.groupedByApp
        #expect(groups.map(\.appBundleID) == ["slack", "mail"])
        #expect(groups[0].items.map(\.id) == ["s2", "s1"])
        #expect(groups[1].items.map(\.id) == ["m1"])
    }
}

extension NotificationStoreTests {
    func appItem(_ id: String, _ bundleID: String, name: String? = nil, at offset: TimeInterval) -> NotificationItem {
        NotificationItem(id: id, appBundleID: bundleID, appName: name ?? bundleID, title: id, body: "", date: t0.addingTimeInterval(offset))
    }

    @Test func hiddenAppsAreExcludedFromItemsGroupsAndUnread() {
        let store = NotificationStore()
        store.ingest([appItem("s1", "slack", at: 0), appItem("m1", "mail", at: 10), appItem("s2", "slack", at: 20)])
        store.hiddenApps = ["slack"]

        #expect(store.items.map(\.id) == ["m1"])
        #expect(store.groupedByApp.map(\.appBundleID) == ["mail"])
        #expect(store.unreadCount == 1)
        #expect(store.allItems.count == 3)
    }

    @Test func isVisibleIsFalseForHiddenAppsAndDismissedItems() {
        let store = NotificationStore()
        let slack = appItem("s1", "slack", at: 0)
        let mail = appItem("m1", "mail", at: 10)
        let dismissed = appItem("m2", "mail", at: 20)
        store.ingest([slack, mail, dismissed])
        store.dismiss(id: "m2")
        store.hiddenApps = ["slack"]

        #expect(!store.isVisible(slack))
        #expect(store.isVisible(mail))
        #expect(!store.isVisible(dismissed))
    }

    @Test func unhidingAnAppBringsItsNotificationsBack() {
        let store = NotificationStore()
        store.ingest([appItem("s1", "slack", at: 0), appItem("m1", "mail", at: 10)])
        store.hiddenApps = ["slack"]
        #expect(store.unreadCount == 1)

        store.hiddenApps = []
        #expect(store.items.map(\.id) == ["m1", "s1"])
        #expect(store.groupedByApp.count == 2)
        #expect(store.unreadCount == 2)
    }

    @Test func knownAppsAreDeduplicatedAndSortedByName() {
        let store = NotificationStore()
        store.ingest([
            appItem("1", "com.zoom", name: "zoom.us", at: 0),
            appItem("2", "com.slack", name: "Slack", at: 10),
            appItem("3", "com.apple.mail", name: "mail", at: 20),
            appItem("4", "com.slack", name: "Slack", at: 30),
        ])
        store.hiddenApps = ["com.slack"]

        let apps = store.knownApps
        #expect(apps.map(\.bundleID) == ["com.apple.mail", "com.slack", "com.zoom"])
        #expect(apps.map(\.name) == ["mail", "Slack", "zoom.us"])
    }
}
