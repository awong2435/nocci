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

        case .hidden, .list:
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
    let onTapAlert: () -> Void

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
