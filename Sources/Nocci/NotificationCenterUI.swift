import AppKit
import ApplicationServices

/// Drives macOS's own Notification Center through Accessibility, so clicking a notification in Nocci does
/// exactly what clicking it in Notification Center does (Slack opens the thread, Claude the session): open the
/// panel, find the same entry, and press it. The technique other open-source apps use (NotificationNanny,
/// agent-desktop); written from their descriptions, not copied.
///
/// Undocumented UI: Apple changes it between releases, so every step fails quietly and callers fall back.
/// Needs Accessibility. Reads entries only to match the one clicked; never logs or keeps their text.
@MainActor
enum NotificationCenterUI {
    static let notificationCenterID = "com.apple.notificationcenterui"
    static let controlCenterID = "com.apple.controlcenter"

    /// Subroles of notification entries (Banner: temporary style; Alert: persistent), and of collapsed stacks.
    static let entrySubroles: Set<String> = ["AXNotificationCenterBanner", "AXNotificationCenterAlert"]
    static let stackSubroles: Set<String> = ["AXNotificationCenterBannerStack", "AXNotificationCenterAlertStack"]

    static var isTrusted: Bool { AXIsProcessTrusted() }

    // MARK: - Panel

    static func appElement(_ bundleID: String) -> AXUIElement? {
        guard let app = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).first else { return nil }
        let element = AXUIElementCreateApplication(app.processIdentifier)
        AXUIElementSetMessagingTimeout(element, 0.5)
        return element
    }

    /// The menu bar clock, which opens and closes the Notification Center panel when pressed.
    static func clockItem() -> AXUIElement? {
        guard let controlCenter = appElement(controlCenterID),
              let bar: AXUIElement = attribute(controlCenter, "AXExtrasMenuBar") else { return nil }
        return children(bar).first { item in
            let id: String? = attribute(item, kAXIdentifierAttribute)
            return id == "com.apple.menuextra.clock" || (id?.lowercased().contains("clock") ?? false)
        }
    }

    /// Whether the panel is open: the app reports AXExpanded (macOS 26+), or it shows the widget editor button.
    static func isPanelOpen() -> Bool {
        guard let center = appElement(notificationCenterID) else { return false }
        if let expanded: Bool = attribute(center, "AXExpanded") { return expanded }
        return find(in: center, limit: 600) { (attribute($0, kAXIdentifierAttribute) as String?) == "widget-editor-button" } != nil
    }

    // MARK: - Opening a notification

    /// Does what clicking the notification in Notification Center does. If it's an on-screen banner, presses it
    /// directly; otherwise opens the panel off-screen, finds the matching entry (expanding `appName`'s collapsed
    /// stack if it's hidden in one; pressing a stack expands it rather than opening anything), presses it, and
    /// makes sure the panel closes. Returns false when it can't: no Accessibility, or the notification was cleared.
    static func open(notificationID: String, appName: String) async -> Bool {
        guard isTrusted else { return false }
        if let banner = entry(matching: notificationID) {
            return press(banner.element)
        }
        guard let session = await openPanelOffScreen() else { return false }
        guard let target = await find(notificationID, expandingStacksOf: [appName]) else {
            session.close()
            return false
        }
        let pressed = press(target.element)
        // Pressing normally opens the app and closes the panel; close it if it didn't.
        try? await Task.sleep(for: .milliseconds(300))
        session.close()
        return pressed
    }

    // MARK: - Closing notifications

    /// Clears notifications from Notification Center, as their Close button would, so dismissing them in Nocci
    /// keeps the two in step. On-screen banners are closed directly; the rest through the panel, opened
    /// off-screen. Returns how many were closed; ones already gone or not found are skipped.
    @discardableResult
    static func close(notificationIDs: [String], appNames: Set<String>) async -> Int {
        guard isTrusted, !notificationIDs.isEmpty else { return 0 }
        var remaining = Set(notificationIDs)
        var closed = 0
        for entry in entries() where remaining.contains(normalizedID(entry.identifier) ?? "") && !entry.isStack {
            if performClose(entry) {
                closed += 1
                remaining.remove(normalizedID(entry.identifier) ?? "")
            }
        }
        guard !remaining.isEmpty, let session = await openPanelOffScreen() else { return closed }
        var expanded = false
        for id in notificationIDs where remaining.contains(id) {
            var target = entry(matching: id)
            if target == nil && !expanded {
                target = await find(id, expandingStacksOf: appNames)
                expanded = true
            }
            // A collapsed stack whose top is this notification: expand it so the row itself can be closed.
            if let found = target, found.isStack {
                _ = press(found.element)
                try? await Task.sleep(for: .milliseconds(300))
                target = entries().first { normalizedID($0.identifier) == id && !$0.isStack }
            }
            if let target, performClose(target) {
                closed += 1
                // Rows shift as one closes; give the list a moment before the next.
                try? await Task.sleep(for: .milliseconds(80))
            }
        }
        session.close()
        return closed
    }

    /// The localized name of Notification Center's Close action ("Close", "Fermer", …), read from Notification
    /// Center itself, with English as the fallback.
    private static let closeActionName: String = Bundle(path: "/System/Library/CoreServices/NotificationCenter.app")?
        .localizedString(forKey: "Close", value: "Close", table: "Localizable") ?? "Close"

    private static func performClose(_ entry: Entry) -> Bool {
        guard let action = entry.action(named: closeActionName) ?? entry.action(named: "Close") else { return false }
        return AXUIElementPerformAction(entry.element, action as CFString) == .success
    }

    // MARK: - Panel session

    /// An open panel to work in. `close()` closes it again unless it was already open before.
    struct PanelSession {
        let clock: AXUIElement
        let wasOpen: Bool

        @MainActor func close() {
            if !wasOpen, isPanelOpen() { _ = press(clock) }
        }
    }

    /// Opens the panel (if it isn't already) and moves it off-screen the moment its window appears: the window
    /// only exists once the panel opens (macOS 26), and entries can still be pressed off-screen.
    private static func openPanelOffScreen() async -> PanelSession? {
        guard let clock = clockItem() else { return nil }
        let wasOpen = isPanelOpen()
        if !wasOpen {
            guard press(clock) else { return nil }
            lastHide = await movePanelOffScreen()
            for _ in 0..<20 where !isPanelOpen() { try? await Task.sleep(for: .milliseconds(50)) }
            // Rows fill in just after the panel reports open.
            try? await Task.sleep(for: .milliseconds(150))
        }
        return PanelSession(clock: clock, wasOpen: wasOpen)
    }

    /// The entry with this ID, expanding the named apps' collapsed stacks if it's hidden in one.
    private static func find(_ notificationID: String, expandingStacksOf appNames: Set<String>) async -> Entry? {
        if let found = entry(matching: notificationID), !found.isStack { return found }
        let stacks = entries().filter { stack in stack.isStack && appNames.contains { stack.isFrom($0) } }
        guard !stacks.isEmpty else { return entry(matching: notificationID) }
        for stack in stacks.prefix(6) { _ = press(stack.element) }
        try? await Task.sleep(for: .milliseconds(400))
        return entries().first { normalizedID($0.identifier) == notificationID && !$0.isStack }
            ?? entry(matching: notificationID)
    }

    /// How the last off-screen move went, for diagnostics: whether it moved, and how long the window was up first.
    static var lastHide: (moved: Bool, visibleFor: Duration)?

    /// Waits up to a second for Notification Center's window to appear and moves every one of its windows far
    /// off-screen. A new window opens in place each time, so nothing needs moving back.
    private static func movePanelOffScreen() async -> (moved: Bool, visibleFor: Duration) {
        let clock = ContinuousClock()
        let start = clock.now
        guard let center = appElement(notificationCenterID) else { return (false, .zero) }
        while clock.now - start < .seconds(1) {
            let windows = (attribute(center, kAXWindowsAttribute) as [AXUIElement]?) ?? []
            if !windows.isEmpty {
                let visibleFor = clock.now - start
                var offScreen = CGPoint(x: 50_000, y: 50_000)
                guard let position = AXValueCreate(.cgPoint, &offScreen) else { return (false, visibleFor) }
                let moved = windows.map { AXUIElementSetAttributeValue($0, kAXPositionAttribute as CFString, position) == .success }
                return (moved.contains(true), visibleFor)
            }
            try? await Task.sleep(for: .milliseconds(3))
        }
        return (false, clock.now - start)
    }

    /// The entry with this notification's ID (Notification Center's IDs are the database's record UUIDs).
    private static func entry(matching notificationID: String) -> Entry? {
        entries().first { normalizedID($0.identifier) == notificationID }
    }

    // MARK: - Entries

    /// Notification entries currently in Notification Center (panel or on-screen banners), with their unique ID
    /// and text, for matching. Stacks are listed as entries too, flagged, since a collapsed stack hides its rows.
    struct Entry {
        let element: AXUIElement
        let identifier: String?
        let title: String?
        let subtitle: String?
        let body: String?
        let isStack: Bool
        let actions: [String]
        /// "App, title, …" as Notification Center describes the entry; used only to tell which app a stack is.
        let summary: String?

        /// Whether this entry or stack is from `appName` (its summary starts with the app name).
        func isFrom(_ appName: String) -> Bool {
            summary?.lowercased().hasPrefix(appName.lowercased()) ?? false
        }

        /// The full action name whose "Name:" line is `name` (custom actions look like "Name:Show Details\n…").
        func action(named name: String) -> String? {
            actions.first { $0 == name || $0.hasPrefix("Name:\(name)\n") || $0 == "Name:\(name)" }
        }
    }

    static func entries() -> [Entry] {
        guard let center = appElement(notificationCenterID) else { return [] }
        var found: [Entry] = []
        walk(center, depth: 0, budget: 1200) { element in
            guard let subrole: String = attribute(element, kAXSubroleAttribute) else { return true }
            let isEntry = entrySubroles.contains(subrole), isStack = stackSubroles.contains(subrole)
            guard isEntry || isStack else { return true }
            var texts: [String: String] = [:]
            walk(element, depth: 0, budget: 60) { child in
                if let id: String = attribute(child, kAXIdentifierAttribute), ["title", "subtitle", "body"].contains(id),
                   let value: String = attribute(child, kAXValueAttribute) {
                    texts[id] = value
                }
                return true
            }
            var names: CFArray?
            AXUIElementCopyActionNames(element, &names)
            found.append(Entry(
                element: element,
                identifier: attribute(element, kAXIdentifierAttribute),
                title: texts["title"], subtitle: texts["subtitle"], body: texts["body"],
                isStack: isStack,
                actions: (names as? [String]) ?? [],
                summary: attribute(element, kAXDescriptionAttribute)
            ))
            return isStack  // look inside stacks for individual rows; entries have no nested entries
        }
        return found
    }

    /// A notification's ID in the form Nocci uses (lowercase hex, no dashes), for comparing with the database's.
    static func normalizedID(_ identifier: String?) -> String? {
        guard let identifier else { return nil }
        let hex = identifier.lowercased().filter { $0.isHexDigit }
        return hex.count == 32 ? hex : nil
    }

    // MARK: - AX helpers

    static func attribute<T>(_ element: AXUIElement, _ name: String) -> T? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success else { return nil }
        return value as? T
    }

    static func children(_ element: AXUIElement) -> [AXUIElement] {
        (attribute(element, kAXChildrenAttribute) as [AXUIElement]?) ?? []
    }

    /// Depth-first walk; `visit` returns whether to descend into the element's children.
    static func walk(_ element: AXUIElement, depth: Int, budget: Int, visit: (AXUIElement) -> Bool) {
        var remaining = budget
        func go(_ element: AXUIElement, _ depth: Int) {
            guard remaining > 0, depth <= 14 else { return }
            remaining -= 1
            guard visit(element) else { return }
            for child in children(element) { go(child, depth + 1) }
        }
        go(element, depth)
    }

    static func find(in root: AXUIElement, limit: Int, where match: (AXUIElement) -> Bool) -> AXUIElement? {
        var result: AXUIElement?
        walk(root, depth: 0, budget: limit) { element in
            if result == nil, match(element) { result = element }
            return result == nil
        }
        return result
    }

    static func press(_ element: AXUIElement) -> Bool {
        AXUIElementPerformAction(element, kAXPressAction as CFString) == .success
    }
}
