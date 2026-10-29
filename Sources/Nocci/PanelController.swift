import AppKit
import Observation
import OSLog
import SwiftUI
import NocciCore

private let log = Logger(subsystem: "local.nocci", category: "panel")

/// What the island shows. `size` and `bottomRadius` animate; content is laid out at its final size.
@MainActor
@Observable
final class PanelPresentation {
    enum Content: Equatable {
        case alert(item: NotificationItem, scrolls: Bool, layoutSize: CGSize)
        case counter(layoutSize: CGSize)
        case list(layoutSize: CGSize)

        /// The size the content lays out at: the island's final size, so text doesn't reflow while it grows.
        var layoutSize: CGSize {
            switch self {
            case .alert(_, _, let size), .counter(let size), .list(let size): size
            }
        }

        /// The window's size: the island, plus room beside the notch for the unread light.
        var windowSize: CGSize {
            switch self {
            case .counter(let size):
                CGSize(width: size.width + 2 * CounterBadge.sideRoom, height: max(size.height, CounterBadge.topInset + CounterBadge.diameter + 4))
            case .alert, .list:
                layoutSize
            }
        }

        var isCounter: Bool {
            if case .counter = self { true } else { false }
        }

        /// Changes when the content should cross-fade. A different alert counts as different content.
        var identity: String {
            switch self {
            case .alert(let item, _, _): "alert-\(item.id)"
            case .counter: "counter"
            case .list: "list"
            }
        }
    }

    var content: Content?
    /// Island size, including the ears and the part behind the notch.
    var size: CGSize = .zero
    var bottomRadius: CGFloat = 8
    var notchHeight: CGFloat = 0
}

/// Turns `PanelModel.state` into the notch panel's frame, visibility, and animation.
@MainActor
final class PanelController: NSObject {
    /// Default alert width (PLAN.md: about 500 to 600 points). M6 makes it adjustable.
    static let alertWidth: CGFloat = 560
    /// Width of the concave ears at the island's top corners.
    static let ear: CGFloat = 6

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
            ear: Self.ear,
            onTapAlert: { [weak model] in model?.dismissAlert() }
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
        guard let screen = NSScreen.nocciTarget else { return nil }
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
        guard let screen = NSScreen.nocciTarget else { return }
        let geometry = screen.notchGeometry
        let notchHeight = geometry.notchSize.height
        let wideWidth = Self.alertWidth + 2 * Self.ear

        switch model.state {
        case .alert:
            guard let item = model.currentAlert else { return morph(to: nil, geometry: geometry) }
            let maxHeight = min(screen.frame.height * 0.6, 520)
            let naturalHeight = AlertCard.naturalHeight(of: item, width: Self.alertWidth, notchHeight: notchHeight)
            let size = CGSize(width: wideWidth, height: min(naturalHeight, maxHeight))
            morph(to: .alert(item: item, scrolls: naturalHeight > maxHeight, layoutSize: size), radius: 22, geometry: geometry)

            // ID and latency only; never notification text.
            guard logAlert else { return }
            let latency = Date().timeIntervalSince(item.date)
            log.notice("alert id=\(item.id, privacy: .public) app=\(item.appBundleID, privacy: .public) latency=\(latency, format: .fixed(precision: 2), privacy: .public)s")

        case .counter:
            // Stay out of the way over full-screen apps, where the menu bar area is plain black.
            guard !FullScreenDetector.isFullScreenAppShowing(on: screen) else { return morph(to: nil, geometry: geometry) }
            // The island tucks back behind the notch; the light sits beside it.
            morph(to: .counter(layoutSize: restingSize(geometry)), geometry: geometry)

        case .list:
            let maxHeight = min(screen.frame.height * 0.75, 700)
            let naturalHeight = NotificationList.naturalHeight(of: model.store, width: Self.alertWidth, notchHeight: notchHeight)
            morph(to: .list(layoutSize: CGSize(width: wideWidth, height: min(naturalHeight, maxHeight))), radius: 22, geometry: geometry)

        case .hidden:
            morph(to: nil, geometry: geometry)
        }
    }

    /// The island at rest: the size of the notch, so it disappears behind it. On screens without a notch, a flat line.
    private func restingSize(_ geometry: NotchGeometry) -> CGSize {
        geometry.hasNotch ? geometry.notchSize : CGSize(width: CounterBadge.pillWidth + 2 * Self.ear, height: 0)
    }

    /// Animates the island from its current shape to `content`'s size, or back into the notch when `content` is nil.
    ///
    /// The window grows to fit both shapes before the animation and shrinks to the final shape after it, so it's
    /// only bigger than what's visible while animating and doesn't sit over clicks meant for other apps.
    private func morph(to content: PanelPresentation.Content?, radius: CGFloat = 8, geometry: NotchGeometry) {
        generation += 1
        let started = generation
        guard content != nil || panel.isVisible else { return }

        let resting = restingSize(geometry)
        if !panel.isVisible {
            // Start from the notch.
            presentation.size = resting
            presentation.bottomRadius = 8
            presentation.content = nil
        }
        presentation.notchHeight = geometry.notchSize.height

        let target = content?.layoutSize ?? resting
        let targetWindow = content?.windowSize ?? resting
        let current = panel.isVisible ? panel.frame.size : resting
        let canvas = CGSize(width: max(current.width, targetWindow.width), height: max(current.height, targetWindow.height))
        panel.setFrame(frame(for: canvas, geometry), display: false)
        // The light is only an indicator; let clicks beside the notch reach the menu bar. Hover still opens the list.
        panel.ignoresMouseEvents = content?.isCounter ?? false
        panel.orderFrontRegardless()

        withAnimation(.spring(duration: 0.45, bounce: 0.22)) {
            presentation.size = target
            presentation.bottomRadius = content == nil ? 8 : radius
            presentation.content = content
        } completion: { [weak self] in
            // Skip if a newer update arrived during the animation; it has already taken over.
            guard let self, generation == started else { return }
            if content == nil {
                panel.orderOut(nil)
            } else {
                panel.setFrame(frame(for: targetWindow, geometry), display: true)
            }
        }
    }

    /// Window frame for an island of `size`, centered on the notch and flush with the top edge.
    private func frame(for size: CGSize, _ geometry: NotchGeometry) -> CGRect {
        geometry.panelFrame(contentSize: CGSize(width: size.width, height: max(0, size.height - geometry.notchSize.height)))
    }
}

/// Root SwiftUI view inside the notch panel: one black island shape, with the current content inside it.
private struct NotchRootView: View {
    let presentation: PanelPresentation
    let store: NotificationStore
    let ear: CGFloat
    let onTapAlert: () -> Void

    var body: some View {
        let shape = IslandShape(ear: ear, bottomRadius: presentation.bottomRadius)
        Color.clear
            .frame(width: presentation.size.width, height: presentation.size.height)
            .overlay(alignment: .top) {
                if let content = presentation.content {
                    contentView(content)
                        .padding(.horizontal, ear)
                        .frame(width: content.layoutSize.width, height: content.layoutSize.height, alignment: .top)
                        .id(content.identity)
                        // Content fades in once the island has started growing, and out quickly before it shrinks.
                        .transition(.asymmetric(
                            insertion: .opacity.animation(.easeOut(duration: 0.2).delay(0.12)),
                            removal: .opacity.animation(.easeIn(duration: 0.1))
                        ))
                }
            }
            .background(shape.fill(.black))
            .clipShape(shape)
            .overlay(alignment: .topTrailing) {
                if presentation.content?.isCounter == true {
                    // Just right of the notch, near the top. The island's ears sit inside the notch at rest.
                    CounterBadge()
                        .offset(x: CounterBadge.gap + CounterBadge.diameter, y: CounterBadge.topInset)
                        .transition(.scale.combined(with: .opacity))
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    @ViewBuilder
    private func contentView(_ content: PanelPresentation.Content) -> some View {
        switch content {
        case .alert(let item, let scrolls, _):
            AlertCard(item: item, notchHeight: presentation.notchHeight, scrolls: scrolls)
                // Temporary: clicking hides the alert. M7 adds swipe to dismiss, M8 makes click open the app.
                .onTapGesture(perform: onTapAlert)
        case .counter:
            // Drawn as an overlay outside the island; see body.
            EmptyView()
        case .list:
            // Always scrollable: notifications that arrive while it's open make it taller than measured.
            NotificationList(store: store, notchHeight: presentation.notchHeight, scrolls: true)
        }
    }
}

extension NSScreen {
    /// The built-in notched screen if there is one, otherwise the menu bar screen.
    static var nocciTarget: NSScreen? {
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
