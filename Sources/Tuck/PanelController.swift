import AppKit
import Observation
import OSLog
import SwiftUI
import TuckCore

private let log = Logger(subsystem: "local.tuck", category: "panel")

/// What the SwiftUI view is showing right now. Changed only after the panel is framed, so animations line up.
@MainActor
@Observable
final class PanelPresentation {
    struct Alert {
        let item: NotificationItem
        let notchHeight: CGFloat
        let scrolls: Bool
    }

    var alert: Alert?
}

/// Turns `PanelModel.state` into the notch panel's frame, visibility, and animation.
@MainActor
final class PanelController: NSObject {
    /// Default alert width (PLAN.md: about 500 to 600 points). M6 makes it adjustable.
    static let alertWidth: CGFloat = 560

    private let model: PanelModel
    private let panel = NotchPanel()
    private let presentation = PanelPresentation()

    init(model: PanelModel) {
        self.model = model
        super.init()

        let hostingView = NSHostingView(rootView: NotchRootView(presentation: presentation) { [weak model] in
            model?.dismissAlert()
        })
        // The panel decides its size; the SwiftUI view just fills it.
        hostingView.sizingOptions = []
        panel.contentView = hostingView

        trackState()
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(screensChanged),
            name: NSApplication.didChangeScreenParametersNotification,
            object: nil
        )
    }

    private func trackState() {
        withObservationTracking {
            _ = model.state
        } onChange: { [weak self] in
            Task { @MainActor in
                self?.update()
                self?.trackState()
            }
        }
    }

    @objc private func screensChanged() {
        update()
    }

    private func update() {
        if let item = model.currentAlert {
            show(item)
        } else {
            hide()
        }
    }

    private func show(_ item: NotificationItem) {
        guard let screen = NSScreen.tuckTarget else { return }
        let geometry = screen.notchGeometry
        let notchHeight = geometry.notchSize.height
        let maxHeight = min(screen.frame.height * 0.6, 520)
        let naturalHeight = AlertCard.naturalHeight(of: item, width: Self.alertWidth, notchHeight: notchHeight)
        let height = min(naturalHeight, maxHeight)

        let frame = geometry.panelFrame(contentSize: CGSize(width: Self.alertWidth, height: height - notchHeight))
        panel.setFrame(frame, display: false)
        panel.orderFrontRegardless()

        withAnimation(.spring(duration: 0.35, bounce: 0.15)) {
            presentation.alert = .init(item: item, notchHeight: notchHeight, scrolls: naturalHeight > maxHeight)
        }
        // ID and latency only; never notification text.
        let latency = Date().timeIntervalSince(item.date)
        log.notice("alert id=\(item.id, privacy: .public) app=\(item.appBundleID, privacy: .public) latency=\(latency, format: .fixed(precision: 2), privacy: .public)s")
    }

    private func hide() {
        guard presentation.alert != nil else {
            panel.orderOut(nil)
            return
        }
        withAnimation(.easeIn(duration: 0.25)) {
            presentation.alert = nil
        } completion: { [weak self] in
            // A new alert may have arrived during the animation.
            guard let self, presentation.alert == nil else { return }
            panel.orderOut(nil)
        }
    }
}

/// Root SwiftUI view inside the notch panel.
private struct NotchRootView: View {
    let presentation: PanelPresentation
    let onTapAlert: () -> Void

    var body: some View {
        ZStack(alignment: .top) {
            if let alert = presentation.alert {
                AlertCard(item: alert.item, notchHeight: alert.notchHeight, scrolls: alert.scrolls)
                    .id(alert.item.id)
                    .transition(.move(edge: .top).combined(with: .opacity))
                    // Temporary: clicking hides the alert. M7 adds swipe to dismiss, M8 makes click open the app.
                    .onTapGesture(perform: onTapAlert)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
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
