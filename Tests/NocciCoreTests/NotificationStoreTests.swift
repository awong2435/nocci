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
