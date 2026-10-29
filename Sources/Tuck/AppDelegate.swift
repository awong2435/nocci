import AppKit
import OSLog
import SwiftUI
import TuckCore

private let log = Logger(subsystem: "local.tuck", category: "panel")

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem?
    private let panel = NotchPanel()
    private let hostingView = NSHostingView(rootView: HelloView(notchHeight: 0))

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Menu bar only, no Dock icon (LSUIElement covers the bundled app; this covers `swift run`).
        NSApp.setActivationPolicy(.accessory)
        setUpStatusItem()

        // Let the panel decide its size; the SwiftUI view just fills it.
        hostingView.sizingOptions = []
        panel.contentView = hostingView
        positionPanel()
        panel.orderFrontRegardless()

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(screensChanged),
            name: NSApplication.didChangeScreenParametersNotification,
            object: nil
        )
    }

    private func setUpStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.button?.image = NSImage(systemSymbolName: "rectangle.topthird.inset.filled", accessibilityDescription: "Tuck")
        let menu = NSMenu()
        menu.addItem(withTitle: "Quit Tuck", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        item.menu = menu
        statusItem = item
    }

    @objc private func screensChanged() {
        positionPanel()
    }

    private func positionPanel() {
        guard let screen = NSScreen.tuckTarget else { return }
        let geometry = screen.notchGeometry
        let contentWidth = geometry.hasNotch ? geometry.notchSize.width + 120 : 220
        let frame = geometry.panelFrame(contentSize: CGSize(width: contentWidth, height: 28))

        hostingView.rootView = HelloView(notchHeight: geometry.notchSize.height)
        panel.setFrame(frame, display: true)

        // Geometry only; never notification content.
        log.notice("screen=\(screen.localizedName, privacy: .public) notch=\(geometry.notchSize.width, privacy: .public)x\(geometry.notchSize.height, privacy: .public) panel=\(NSStringFromRect(frame), privacy: .public)")
    }
}

extension NSScreen {
    /// The built-in notched screen if there is one, otherwise the menu bar screen.
    static var tuckTarget: NSScreen? {
        screens.first { $0.safeAreaInsets.top > 0 } ?? screens.first
    }

    var notchGeometry: NotchGeometry {
        NotchGeometry(
            screenFrame: frame,
            safeAreaTop: safeAreaInsets.top,
            auxiliaryLeftWidth: auxiliaryTopLeftArea?.width,
            auxiliaryRightWidth: auxiliaryTopRightArea?.width
        )
    }
}
