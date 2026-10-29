import AppKit
import SwiftUI

/// Borderless, non-activating panel that sits over the notch without taking focus.
final class NotchPanel: NSPanel {
    init() {
        super.init(
            contentRect: .zero,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        isFloatingPanel = true
        // Above the menu bar so it can cover the notch area.
        level = NSWindow.Level(rawValue: NSWindow.Level.mainMenu.rawValue + 3)
        collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        hidesOnDeactivate = false
        isMovable = false
        isReleasedWhenClosed = false
        // No system zoom or fade when ordering in or out; the island's own morph is the only animation.
        animationBehavior = .none
    }

    /// Gets every scroll event aimed at this panel first; return true to consume it (a swipe to dismiss).
    /// Done here rather than with an event monitor, which doesn't see them while Nocci isn't the active app.
    var scrollInterceptor: ((NSEvent) -> Bool)?

    override func sendEvent(_ event: NSEvent) {
        if event.type == .scrollWheel, scrollInterceptor?(event) == true { return }
        super.sendEvent(event)
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    // AppKit normally pushes windows below the menu bar; keep the frame exactly where it's put.
    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect {
        frameRect
    }
}

/// Hosting view for the panel. The panel never becomes key, so every click is a "first" click; accept it so
/// SwiftUI gestures (tapping an alert) fire instead of the click being used only to focus the window.
final class FirstClickHostingView<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}
