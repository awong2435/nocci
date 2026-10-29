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
    enum Content: Equatable {
        case alert(item: NotificationItem, notchHeight: CGFloat, scrolls: Bool)
        case counter
        case list(notchHeight: CGFloat)

        var isAlert: Bool {
            if case .alert = self { true } else { false }
        }
    }

    var content: Content?
}

/// Turns `PanelModel.state` into the notch panel's frame, visibility, and animation.
@MainActor
final class PanelController: NSObject {
    /// Default alert width (PLAN.md: about 500 to 600 points). M6 makes it adjustable.
    static let alertWidth: CGFloat = 560

    private let model: PanelModel
    private let panel = NotchPanel()
    private let presentation = PanelPresentation()
    /// Bumped on every update so a finishing animation can tell it's been superseded.
    private var generation = 0
    private var hoverTracker: HoverTracker?

    init(model: PanelModel) {
        self.model = model
        super.init()

        let hostingView = NSHostingView(rootView: NotchRootView(
            presentation: presentation,
            store: model.store,
            onTapAlert: { [weak model] in model?.dismissAlert() },
            onTapCounter: { [weak model] in model?.openList() }
        ))
        // The panel decides its size; the SwiftUI view just fills it.
        hostingView.sizingOptions = []
        panel.contentView = hostingView
        // So the local mouse monitor sees movement over the panel itself.
        panel.acceptsMouseMovedEvents = true

        hoverTracker = HoverTracker(
            decide: { [weak self] point in self?.hoverAction(at: point) },
            perform: { [weak model] action in
                switch action {
                case .open: model?.openList()
                case .close: model?.closeList()
                }
            }
        )

        trackState()
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(screensChanged),
            name: NSApplication.didChangeScreenParametersNotification,
            object: nil
        )
        // Entering or leaving a full-screen app changes the active space or the frontmost app.
        for name in [NSWorkspace.activeSpaceDidChangeNotification, NSWorkspace.didActivateApplicationNotification] {
            NSWorkspace.shared.notificationCenter.addObserver(self, selector: #selector(screensChanged), name: name, object: nil)
        }
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

    /// Hovering the notch opens the list (as does the counter, which sits just below it).
    /// Once open, the list stays while the mouse is over the notch or the panel.
    private func hoverAction(at point: NSPoint) -> HoverTracker.Action? {
        guard let screen = NSScreen.tuckTarget else { return nil }
        // One extra point upward so the very top pixel row counts.
        let hotZone = screen.notchGeometry
            .hotZone(fallbackSize: CGSize(width: 200, height: NSStatusBar.system.thickness))
            .insetBy(dx: 0, dy: -1)
        let overPanel = panel.isVisible && panel.frame.contains(point)

        switch model.state {
        case .list:
            return hotZone.contains(point) || overPanel ? nil : .close
        case .counter:
            return hotZone.contains(point) || overPanel ? .open : nil
        case .hidden, .alert:
            return hotZone.contains(point) ? .open : nil
        }
    }

    @objc private func screensChanged() {
        update(logAlert: false)
    }

    private func update(logAlert: Bool = true) {
        guard let screen = NSScreen.tuckTarget else { return }
        let geometry = screen.notchGeometry

        switch model.state {
        case .alert:
            guard let item = model.currentAlert else { return present(nil, frame: nil) }
            let notchHeight = geometry.notchSize.height
            let maxHeight = min(screen.frame.height * 0.6, 520)
            let naturalHeight = AlertCard.naturalHeight(of: item, width: Self.alertWidth, notchHeight: notchHeight)
            let height = min(naturalHeight, maxHeight)
            let frame = geometry.panelFrame(contentSize: CGSize(width: Self.alertWidth, height: height - notchHeight))
            present(.alert(item: item, notchHeight: notchHeight, scrolls: naturalHeight > maxHeight), frame: frame)

            // ID and latency only; never notification text.
            guard logAlert else { return }
            let latency = Date().timeIntervalSince(item.date)
            log.notice("alert id=\(item.id, privacy: .public) app=\(item.appBundleID, privacy: .public) latency=\(latency, format: .fixed(precision: 2), privacy: .public)s")

        case .counter:
            // Stay out of the way over full-screen apps, where the menu bar area is plain black.
            guard !FullScreenDetector.isFullScreenAppShowing(on: screen) else { return present(nil, frame: nil) }
            let width = geometry.hasNotch ? geometry.notchSize.width : CounterBadge.pillWidth
            present(.counter, frame: geometry.panelFrame(contentSize: CGSize(width: width, height: CounterBadge.lipHeight)))

        case .list:
            let notchHeight = geometry.notchSize.height
            let maxHeight = min(screen.frame.height * 0.75, 700)
            let naturalHeight = NotificationList.naturalHeight(of: model.store, width: Self.alertWidth, notchHeight: notchHeight)
            let height = min(naturalHeight, maxHeight)
            present(.list(notchHeight: notchHeight), frame: geometry.panelFrame(contentSize: CGSize(width: Self.alertWidth, height: height - notchHeight)))

        case .hidden:
            present(nil, frame: nil)
        }
    }

    /// Shows `content` in a panel at `frame`, animating out whatever was there.
    /// Alert-to-alert swaps in place; any other change animates the old content out first, then resizes.
    private func present(_ content: PanelPresentation.Content?, frame: CGRect?) {
        generation += 1
        let current = presentation.content

        guard let content, let frame else {
            guard current != nil else { return panel.orderOut(nil) }
            animateOut(then: { [weak self] in self?.panel.orderOut(nil) })
            return
        }

        if current == nil || (current?.isAlert == true && content.isAlert) {
            animateIn(content, frame: frame)
        } else if current != content {
            animateOut(then: { [weak self] in self?.animateIn(content, frame: frame) })
        }
    }

    private func animateIn(_ content: PanelPresentation.Content, frame: CGRect) {
        panel.setFrame(frame, display: false)
        panel.orderFrontRegardless()
        withAnimation(.spring(duration: 0.35, bounce: 0.15)) {
            presentation.content = content
        }
    }

    private func animateOut(then next: @escaping @MainActor () -> Void) {
        let started = generation
        withAnimation(.easeIn(duration: 0.2)) {
            presentation.content = nil
        } completion: { [weak self] in
            // Skip if a newer update arrived during the animation; it has already taken over.
            guard let self, generation == started else { return }
            next()
        }
    }
}

/// Root SwiftUI view inside the notch panel.
private struct NotchRootView: View {
    let presentation: PanelPresentation
    let store: NotificationStore
    let onTapAlert: () -> Void
    let onTapCounter: () -> Void

    var body: some View {
        ZStack(alignment: .top) {
            switch presentation.content {
            case .alert(let item, let notchHeight, let scrolls):
                AlertCard(item: item, notchHeight: notchHeight, scrolls: scrolls)
                    .id(item.id)
                    .transition(.move(edge: .top).combined(with: .opacity))
                    // Temporary: clicking hides the alert. M7 adds swipe to dismiss, M8 makes click open the app.
                    .onTapGesture(perform: onTapAlert)
            case .counter:
                CounterBadge()
                    .transition(.opacity)
                    .onTapGesture(perform: onTapCounter)
            case .list(let notchHeight):
                // Always scrollable: notifications that arrive while it's open make it taller than measured.
                NotificationList(store: store, notchHeight: notchHeight, scrolls: true)
                    .transition(.move(edge: .top).combined(with: .opacity))
            case nil:
                EmptyView()
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
