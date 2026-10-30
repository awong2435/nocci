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
    /// directly; otherwise opens the panel, presses the matching entry, and makes sure the panel closes. Returns
    /// false (having changed nothing visible for long) when it can't: no Accessibility, the entry was cleared, or
    /// it's hidden inside a collapsed stack.
    static func open(notificationID: String) async -> Bool {
        guard isTrusted else { return false }
        if let banner = entry(matching: notificationID) {
            return press(banner.element)
        }
        guard let clock = clockItem() else { return false }
        let wasOpen = isPanelOpen()
        if !wasOpen {
            guard press(clock) else { return false }
            for _ in 0..<20 where !isPanelOpen() { try? await Task.sleep(for: .milliseconds(50)) }
            // Rows fill in just after the panel reports open.
            try? await Task.sleep(for: .milliseconds(150))
        }
        guard let target = entry(matching: notificationID) else {
            if !wasOpen, isPanelOpen() { _ = press(clock) }
            return false
        }
        let pressed = press(target.element)
        // Pressing normally opens the app and closes the panel; close it if it didn't.
        try? await Task.sleep(for: .milliseconds(300))
        if !wasOpen, isPanelOpen() { _ = press(clock) }
        return pressed
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
                actions: (names as? [String]) ?? []
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
