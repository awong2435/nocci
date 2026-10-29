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
        /// The island tucked behind the notch, with the unread indicator beside it.
        case counter(layoutSize: CGSize, style: IndicatorStyle, side: IndicatorSide)
        case list(layoutSize: CGSize)

        /// The size the content lays out at: the island's final size, so text doesn't reflow while it grows.
        var layoutSize: CGSize {
            switch self {
            case .alert(_, _, let size), .counter(let size, _, _), .list(let size): size
            }
        }

        /// The window's size: the island, plus room beside the notch for the unread indicator.
        var windowSize: CGSize {
            switch self {
            case .counter(let size, let style, _):
                CGSize(width: size.width + 2 * CounterBadge.sideRoom(for: style), height: max(size.height, CounterBadge.topInset + 16))
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

/// Turns `PanelModel.state` and the settings into the island's frame, visibility, and animation.
@MainActor
final class PanelController: NSObject {
    /// A fixed state shown while the settings window is open, so changes can be seen as they're made.
    enum Preview: String, CaseIterable {
        case alert, list, light
    }

    /// Width of the concave ears at the island's top corners.
    static let ear: CGFloat = 6

    /// Shown in the alert preview. Not a real notification.
    private static let sampleAlert = NotificationItem(
        id: "nocci-preview",
        appBundleID: "local.nocci",
        appName: "Nocci",
        title: "Preview",
        subtitle: "This is how alerts look",
        body: "Change the settings and watch this card update. Close Settings to go back to your notifications.",
        date: Date()
    )

    var preview: Preview? {
        didSet { if preview != oldValue { update(logAlert: false) } }
    }

    private let model: PanelModel
    private let settings: NocciSettings
    private let openSettings: () -> Void
    private let panel = NotchPanel()
    private let presentation = PanelPresentation()
    /// Bumped on every update so a finishing animation can tell it's been superseded.
    private var generation = 0
    private var hoverTracker: HoverTracker?
    private var rightClickMonitors: [Any] = []
    /// The screen the island is currently on.
    private var currentScreenID: CGDirectDisplayID?

    init(model: PanelModel, settings: NocciSettings, openSettings: @escaping () -> Void) {
        self.model = model
        self.settings = settings
        self.openSettings = openSettings
        super.init()

        let hostingView = FirstClickHostingView(rootView: NotchRootView(
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
        watchRightClicks()

        trackState()
        trackSettings()
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

    private func trackSettings() {
        withObservationTracking {
            _ = settings.panelWidth
            _ = settings.indicatorStyle
            _ = settings.indicatorSide
            _ = settings.screenChoice
        } onChange: { [weak self] in
            Task { @MainActor in
                self?.update(logAlert: false)
                self?.trackSettings()
            }
        }
    }

    /// Right-clicking the notch (or the island) opens Settings. Mouse monitors need no permission.
    private func watchRightClicks() {
        let global = NSEvent.addGlobalMonitorForEvents(matching: .rightMouseDown) { [weak self] _ in
            self?.rightClicked(at: NSEvent.mouseLocation)
        }
        let local = NSEvent.addLocalMonitorForEvents(matching: .rightMouseDown) { [weak self] event in
            self?.rightClicked(at: NSEvent.mouseLocation)
            return event
        }
        rightClickMonitors = [global, local].compactMap { $0 }
    }

    private func rightClicked(at point: NSPoint) {
        guard let screen = targetScreen() else { return }
        if hotZone(on: screen).contains(point) || (panel.isVisible && panel.frame.contains(point)) {
            openSettings()
        }
    }

    // MARK: - Screens

    /// The screen chosen in Settings. Falls back to the notched or main screen if the chosen one isn't connected.
    private func targetScreen() -> NSScreen? {
        let notched = NSScreen.screens.first { $0.safeAreaInsets.top > 0 } ?? NSScreen.screens.first
        switch settings.screenChoice {
        case .notched:
            return notched
        case .main:
            return NSScreen.screens.first
        case .followMouse:
            let mouse = NSEvent.mouseLocation
            return NSScreen.screens.first { $0.frame.contains(mouse) } ?? notched
        case .named(let name):
            return NSScreen.screens.first { $0.localizedName == name } ?? notched
        }
    }

    /// The notch, or a strip at the top center of screens without one, with one extra point upward so the
    /// very top pixel row counts.
    private func hotZone(on screen: NSScreen) -> CGRect {
        screen.notchGeometry
            .hotZone(fallbackSize: CGSize(width: 200, height: NSStatusBar.system.thickness))
            .insetBy(dx: 0, dy: -1)
    }

    /// Hovering the notch opens the list. Once open, it stays while the mouse is over the notch or the island.
    private func hoverAction(at point: NSPoint) -> HoverTracker.Action? {
        guard preview == nil, let screen = targetScreen() else { return nil }

        // Following the mouse: move the light (or nothing) to the screen the mouse is now on.
        if screen.displayID != currentScreenID, model.state == .counter || model.state == .hidden {
            update(logAlert: false)
        }

        let inHotZone = hotZone(on: screen).contains(point)
        let overPanel = panel.isVisible && panel.frame.contains(point)
        switch model.state {
        case .list:
            return inHotZone || overPanel ? nil : .close
        case .counter:
            return inHotZone || overPanel ? .open : nil
        case .hidden, .alert:
            return inHotZone ? .open : nil
        }
    }

    @objc private func screensChanged() {
        update(logAlert: false)
    }

    // MARK: - Layout

    private func update(logAlert: Bool = true) {
        guard let screen = targetScreen() else { return }
        let geometry = screen.notchGeometry
        let notchHeight = geometry.notchSize.height
        let contentWidth = CGFloat(settings.panelWidth)
        let wideWidth = contentWidth + 2 * Self.ear

        // Moving to another screen: drop what's showing so the island grows from the new screen's notch.
        if screen.displayID != currentScreenID {
            generation += 1
            panel.orderOut(nil)
            currentScreenID = screen.displayID
        }

        let state: PanelState = switch preview {
        case .alert: .alert(Self.sampleAlert.id)
        case .list: .list
        case .light: .counter
        case nil: model.state
        }

        switch state {
        case .alert:
            guard let item = preview == .alert ? Self.sampleAlert : model.currentAlert else {
                return morph(to: nil, geometry: geometry)
            }
            let maxHeight = min(screen.frame.height * 0.6, 520)
            let naturalHeight = AlertCard.naturalHeight(of: item, width: contentWidth, notchHeight: notchHeight)
            let size = CGSize(width: wideWidth, height: min(naturalHeight, maxHeight))
            morph(to: .alert(item: item, scrolls: naturalHeight > maxHeight, layoutSize: size), radius: 22, geometry: geometry)

            // ID and latency only; never notification text.
            guard logAlert, preview == nil else { return }
            let latency = Date().timeIntervalSince(item.date)
            log.notice("alert id=\(item.id, privacy: .public) app=\(item.appBundleID, privacy: .public) latency=\(latency, format: .fixed(precision: 2), privacy: .public)s")

        case .counter:
            // The island tucks back behind the notch; the indicator sits beside it. Screens without a notch show
            // nothing at rest: alerts still drop in, and hovering the top center still opens the list.
            guard settings.indicatorStyle != .off, geometry.hasNotch else { return morph(to: nil, geometry: geometry) }
            let counter = PanelPresentation.Content.counter(
                layoutSize: restingSize(geometry),
                style: settings.indicatorStyle,
                side: settings.indicatorSide
            )
            morph(to: counter, geometry: geometry)

        case .list:
            let maxHeight = min(screen.frame.height * 0.75, 700)
            let naturalHeight = NotificationList.naturalHeight(of: model.store, width: contentWidth, notchHeight: notchHeight)
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
        // The indicator is only an indicator; let clicks beside the notch reach the menu bar. Hover still opens the list.
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
            .overlay(alignment: indicatorAlignment) {
                if case .counter(_, let style, let side) = presentation.content {
                    // Beside the notch, near the top. The island's ears sit inside the notch at rest.
                    CounterBadge(style: style, count: store.unreadCount)
                        .fixedSize()
                        .alignmentGuide(side == .right ? .leading : .trailing) { _ in 0 }
                        .offset(x: side == .right ? CounterBadge.gap : -CounterBadge.gap, y: CounterBadge.topInset)
                        .transition(.scale.combined(with: .opacity))
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    /// The indicator hangs off the island's right or left top corner.
    private var indicatorAlignment: Alignment {
        if case .counter(_, _, .left) = presentation.content { .topLeading } else { .topTrailing }
    }

    @ViewBuilder
    private func contentView(_ content: PanelPresentation.Content) -> some View {
        switch content {
        case .alert(let item, let scrolls, _):
            AlertCard(item: item, notchHeight: presentation.notchHeight, scrolls: scrolls)
                // The whole card, not just its text.
                .contentShape(Rectangle())
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
    var notchGeometry: NotchGeometry {
        NotchGeometry(
            screenFrame: frame,
            safeAreaTop: safeAreaInsets.top,
            auxiliaryLeftWidth: auxiliaryTopLeftArea?.width,
            auxiliaryRightWidth: auxiliaryTopRightArea?.width
        )
    }

    var displayID: CGDirectDisplayID? {
        deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID
    }
}
