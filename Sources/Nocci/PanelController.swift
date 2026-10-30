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
    /// The unread indicator's look and side.
    struct Indicator: Equatable {
        let style: IndicatorStyle
        let side: IndicatorSide
    }

    enum Content: Equatable {
        /// `stacked`: how many older alerts peek out below this one (0 to 2).
        case alert(item: NotificationItem, scrolls: Bool, layoutSize: CGSize, stacked: Int)
        /// The island at rest: tucked behind the notch, or widened around it to show a plugin's compact views
        /// (media while playing), with the unread indicator beside it when there's something unread.
        case rest(layoutSize: CGSize, indicator: Indicator?, compactPluginID: String?)
        /// The open island with the turned-on plugins' sections.
        case expanded(layoutSize: CGSize)

        /// The size the content lays out at: the island's final size, so text doesn't reflow while it grows.
        var layoutSize: CGSize {
            switch self {
            case .alert(_, _, let size, _), .rest(let size, _, _), .expanded(let size): size
            }
        }

        /// The window's size: the island, plus room beside it for the unread indicator.
        var windowSize: CGSize {
            switch self {
            case .rest(let size, let indicator?, _):
                CGSize(
                    width: size.width + 2 * CounterBadge.sideRoom(for: indicator.style),
                    height: max(size.height, CounterBadge.topInset + 16)
                )
            case .alert(_, _, let size, let stacked):
                CGSize(width: size.width, height: size.height + Self.stackLedge * CGFloat(stacked))
            case .rest, .expanded:
                layoutSize
            }
        }

        /// How far each stacked alert peeks out below the one in front.
        static let stackLedge: CGFloat = 7

        var isRest: Bool {
            if case .rest = self { true } else { false }
        }

        /// Changes when the content should cross-fade. A different alert counts as different content.
        var identity: String {
            switch self {
            case .alert(let item, _, _, _): "alert-\(item.id)"
            case .rest(_, _, let compact): "rest-\(compact ?? "none")"
            case .expanded: "expanded"
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
    private let plugins: [any NocciPlugin]
    private let openSettings: () -> Void
    private let panel = NotchPanel()
    private let presentation = PanelPresentation()
    /// Bumped on every update so a finishing animation can tell it's been superseded.
    private var generation = 0
    private var hoverTracker: HoverTracker?
    private var rightClickMonitors: [Any] = []
    /// The screen the island is currently on.
    private var currentScreenID: CGDirectDisplayID?
    private let swipeTracker = SwipeTracker()
    /// Watches for Escape, only while an alert or the list is open. See `watchEscape(_:)`.
    private var escapeMonitor: Any?
    /// Mouse x and width when an edge drag started; nil when not resizing.
    private var resizeStart: (mouseX: CGFloat, width: Double)?

    init(model: PanelModel, settings: NocciSettings, plugins: [any NocciPlugin], openSettings: @escaping () -> Void) {
        self.model = model
        self.settings = settings
        self.plugins = plugins
        self.openSettings = openSettings
        super.init()

        let actions = NotificationActions(
            open: { [weak self] item in self?.open(item) },
            openList: { [model, settings] in
                model.openList(marksRead: settings.activePlugins.contains("notifications"))
            },
            dismiss: { [weak model] ids in ids.forEach { model?.dismiss(id: $0) } }
        )
        let hostingView = FirstClickHostingView(rootView: NotchRootView(
            presentation: presentation,
            store: model.store,
            settings: settings,
            plugins: Dictionary(uniqueKeysWithValues: plugins.map { ($0.id, $0) }),
            ear: Self.ear,
            onResize: { [weak self] event in self?.resize(event) }
        )
        .environment(\.swipeTracker, swipeTracker)
        .environment(\.notificationActions, actions))
        // The panel decides its size; the SwiftUI view just fills it.
        hostingView.sizingOptions = []
        panel.contentView = hostingView
        // So the local mouse monitor sees movement over the panel itself.
        panel.acceptsMouseMovedEvents = true

        hoverTracker = HoverTracker(
            decide: { [weak self] point in self?.hoverAction(at: point) },
            perform: { [model, settings] action in
                // Opening only counts as reading notifications if their section is actually shown.
                let showsNotifications = settings.activePlugins.contains("notifications")
                switch action {
                case .open: model.openList(marksRead: showsNotifications)
                case .close: model.closeList(marksRead: showsNotifications)
                }
            }
        )
        watchRightClicks()
        swipeTracker.onDismiss = { [weak model] id in model?.dismiss(id: id) }
        // Two-finger swipes arrive as scroll events on the panel under the pointer.
        panel.scrollInterceptor = { [weak self] event in
            guard let self, let view = panel.contentView else { return false }
            return swipeTracker.handleScroll(event, in: view)
        }

        trackState()
        trackSettings()
        trackPlugins()
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
            _ = settings.hideFromScreenRecordings
            _ = settings.fontScale
            _ = settings.pluginOrder
            _ = settings.enabledPlugins
        } onChange: { [weak self] in
            Task { @MainActor in
                self?.update(logAlert: false)
                self?.trackSettings()
            }
        }
    }

    /// Re-lays out when a plugin starts or stops having something to show (media starts playing).
    private func trackPlugins() {
        withObservationTracking {
            for plugin in plugins {
                _ = plugin.hasContent
                _ = plugin.showsCompact
                // Media's section changes height between its idle row and the full player, and with a message line.
                // The list grows or shrinks as groups expand and cards are dismissed.
                if let notifications = plugin as? NotificationsPlugin {
                    _ = notifications.listState.expanded
                    _ = notifications.store.items.count
                }
                if let media = plugin as? MediaPlugin {
                    _ = media.hasTrack
                    _ = media.message
                    _ = media.connectableApp
                    _ = media.deniedApp
                }
            }
        } onChange: { [weak self] in
            Task { @MainActor in
                self?.update(logAlert: false)
                self?.trackPlugins()
            }
        }
    }

    /// Turned-on plugins in display order.
    private var activePlugins: [any NocciPlugin] {
        settings.activePlugins.compactMap { id in plugins.first { $0.id == id } }
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

    /// Escape closes the list or the alert. Seeing keys pressed in other apps needs Accessibility; without it the
    /// monitor simply never fires (no prompt). The monitor exists only while something is open, looks only at
    /// whether the key is Escape, and records nothing.
    private func watchEscape(_ open: Bool) {
        if open, escapeMonitor == nil {
            escapeMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
                guard event.keyCode == 53 else { return }  // Escape
                self?.escapePressed()
            }
        } else if !open, let monitor = escapeMonitor {
            NSEvent.removeMonitor(monitor)
            escapeMonitor = nil
        }
    }

    private func escapePressed() {
        guard preview == nil else { return }
        switch model.state {
        case .list: model.closeList(marksRead: settings.activePlugins.contains("notifications"))
        case .alert: model.dismissAlert()
        case .counter, .hidden: break
        }
    }

    /// Opens the app a notification came from, then collapses the alert or closes the island.
    private func open(_ item: NotificationItem) {
        // Straight to the event, conversation, or message when the notification says where; otherwise the app.
        if let link = item.actionURL {
            NSWorkspace.shared.open(link)
        } else if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: item.appBundleID) {
            NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
        }
        switch model.state {
        case .alert: model.dismissAlert()
        case .list: model.closeList(marksRead: settings.activePlugins.contains("notifications"))
        case .counter, .hidden: break
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
        guard preview == nil, resizeStart == nil, let screen = targetScreen() else { return nil }

        // Following the mouse: move the light (or nothing) to the screen the mouse is now on.
        if screen.displayID != currentScreenID, model.state == .counter || model.state == .hidden {
            update(logAlert: false)
        }

        let inHotZone = hotZone(on: screen).contains(point)
        let overPanel = panel.isVisible && panel.frame.contains(point)
        switch model.state {
        case .list:
            return inHotZone || overPanel ? nil : .close
        case .counter, .hidden:
            // At rest the panel is just the indicator or a plugin's compact views beside the notch.
            return inHotZone || overPanel ? .open : nil
        case .alert:
            return inHotZone ? .open : nil
        }
    }

    @objc private func screensChanged() {
        update(logAlert: false)
    }

    // MARK: - Resizing

    enum ResizeEvent {
        /// Dragging the left (-1) or right (+1) edge.
        case drag(edge: CGFloat)
        case end
        /// Double-click: back to the default width.
        case reset
    }

    /// Both edges move together, so the island stays centered on the notch: dragging an edge out by 10 pt widens
    /// it by 20. Measured from the global mouse position, not inside the panel, so resizing the panel under the
    /// cursor doesn't feed back into the drag.
    private func resize(_ event: ResizeEvent) {
        switch event {
        case .drag(let edge):
            let mouseX = NSEvent.mouseLocation.x
            let start = resizeStart ?? (mouseX, settings.panelWidth)
            resizeStart = start
            // Just under the screen's width at most.
            let screenLimit = Double((targetScreen()?.frame.width ?? 2000) - 40 - 2 * Self.ear)
            let upper = max(NocciSettings.widthRange.lowerBound, min(NocciSettings.widthRange.upperBound, screenLimit))
            settings.panelWidth = SymmetricResize.width(
                edge: edge, startWidth: start.width, startX: start.mouseX, currentX: mouseX,
                range: NocciSettings.widthRange.lowerBound...upper
            )
        case .end:
            resizeStart = nil
        case .reset:
            resizeStart = nil
            settings.panelWidth = NocciSettings.defaultWidth
        }
    }

    // MARK: - Layout

    private func update(logAlert: Bool = true) {
        // Out of screenshots and recordings when asked; still visible on screen.
        panel.sharingType = settings.hideFromScreenRecordings ? .none : .readOnly
        guard let screen = targetScreen() else { return }
        let geometry = screen.notchGeometry
        let notchHeight = geometry.notchSize.height
        let contentWidth = CGFloat(settings.panelWidth)
        let wideWidth = contentWidth + 2 * Self.ear
        let fontScale = CGFloat(settings.fontScale)

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
        // Only alerts and the open island have edge handles; a drag can't still be going on otherwise.
        if case .alert = state {} else if state != .list { resizeStart = nil }
        let isOpen = if case .alert = state { true } else { state == .list }
        watchEscape(isOpen && preview == nil)

        switch state {
        case .alert:
            guard let item = preview == .alert ? Self.sampleAlert : model.currentAlert else {
                return morph(to: nil, geometry: geometry)
            }
            let maxHeight = min(screen.frame.height * 0.6, 520)
            let naturalHeight = AlertCard.naturalHeight(of: item, width: contentWidth, notchHeight: notchHeight, fontScale: fontScale)
            let size = CGSize(width: wideWidth, height: min(naturalHeight, maxHeight))
            let stacked = preview == .alert ? 0 : model.stackedAlerts.count
            morph(to: .alert(item: item, scrolls: naturalHeight > maxHeight, layoutSize: size, stacked: stacked), radius: 22, geometry: geometry)

            // ID and latency only; never notification text.
            guard logAlert, preview == nil else { return }
            let latency = Date().timeIntervalSince(item.date)
            log.notice("alert id=\(item.id, privacy: .public) app=\(item.appBundleID, privacy: .public) latency=\(latency, format: .fixed(precision: 2), privacy: .public)s")

        case .counter, .hidden:
            // Screens without a notch show nothing at rest: alerts still drop in, and hovering the top center
            // still opens the island.
            guard geometry.hasNotch else { return morph(to: nil, geometry: geometry) }
            let showsIndicator = state == .counter && settings.indicatorStyle != .off
            let compact = activePlugins.first { $0.showsCompact }
            guard showsIndicator || compact != nil else { return morph(to: nil, geometry: geometry) }

            // Tucked behind the notch, or widened around it for a plugin's compact views.
            var size = restingSize(geometry)
            if compact != nil {
                size.width += 2 * (compactWingWidth + Self.ear)
            }
            let rest = PanelPresentation.Content.rest(
                layoutSize: size,
                indicator: showsIndicator ? .init(style: settings.indicatorStyle, side: settings.indicatorSide) : nil,
                compactPluginID: compact?.id
            )
            morph(to: rest, radius: compact == nil ? 8 : 14, geometry: geometry)

        case .list:
            let sections = activePlugins.filter(\.hasContent)
            let maxHeight = min(screen.frame.height * 0.75, 700)
            let naturalHeight = ExpandedView.naturalHeight(of: sections, width: contentWidth, notchHeight: notchHeight, fontScale: fontScale)
            morph(to: .expanded(layoutSize: CGSize(width: wideWidth, height: min(naturalHeight, maxHeight))), radius: 22, geometry: geometry)
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
        panel.ignoresMouseEvents = content?.isRest ?? false
        panel.orderFrontRegardless()

        // Follow the mouse exactly while an edge is being dragged; spring otherwise.
        withAnimation(resizeStart == nil ? .spring(duration: 0.45, bounce: 0.22) : nil) {
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
    let settings: NocciSettings
    let plugins: [String: any NocciPlugin]
    let ear: CGFloat
    let onResize: (PanelController.ResizeEvent) -> Void
    @Environment(\.swipeTracker) private var swipeTracker
    @Environment(\.notificationActions) private var actions

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
            .background(alignment: .bottom) { stackLayers }
            .overlay(alignment: .leading) { if isResizable { resizeHandle(edge: -1) } }
            .overlay(alignment: .trailing) { if isResizable { resizeHandle(edge: 1) } }
            .overlay(alignment: indicatorAlignment) {
                if case .rest(_, let indicator?, _) = presentation.content {
                    // Beside the island, near the top.
                    CounterBadge(style: indicator.style, count: store.unreadCount)
                        .fixedSize()
                        .alignmentGuide(indicator.side == .right ? .leading : .trailing) { _ in 0 }
                        .offset(x: indicator.side == .right ? CounterBadge.gap : -CounterBadge.gap, y: CounterBadge.topInset)
                        .transition(.scale.combined(with: .opacity))
                }
            }
            .environment(\.nocciFontScale, CGFloat(settings.fontScale))
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    /// Older alerts that arrived together peek out below the current one, like a Notification Center stack.
    @ViewBuilder
    private var stackLayers: some View {
        if case .alert(_, _, _, let stacked) = presentation.content, stacked > 0 {
            ZStack(alignment: .bottom) {
                ForEach(Array((1...stacked).reversed()), id: \.self) { level in
                    UnevenRoundedRectangle(bottomLeadingRadius: 18, bottomTrailingRadius: 18)
                        .fill(Color(white: 0.16 - 0.04 * CGFloat(level)))
                        .frame(height: 30)
                        .padding(.horizontal, ear + 14 * CGFloat(level))
                        .offset(y: PanelPresentation.Content.stackLedge * CGFloat(level))
                }
            }
            .transition(.opacity)
        }
    }

    /// Alerts and the open island can be resized by dragging either side edge.
    private var isResizable: Bool {
        switch presentation.content {
        case .alert, .expanded: true
        case .rest, nil: false
        }
    }

    /// A thin invisible strip along one side edge (inside the ear) with a resize cursor.
    private func resizeHandle(edge: CGFloat) -> some View {
        Color.clear
            .frame(width: 8)
            .padding(.top, presentation.notchHeight)
            .padding(edge < 0 ? .leading : .trailing, ear)
            .contentShape(Rectangle())
            // Set, not push/pop: the handle can vanish under the cursor (alert expires), and an unmatched push
            // would leave the resize cursor stuck.
            .onContinuousHover { phase in
                switch phase {
                case .active: NSCursor.resizeLeftRight.set()
                case .ended: NSCursor.arrow.set()
                }
            }
            .gesture(
                DragGesture(minimumDistance: 1, coordinateSpace: .global)
                    .onChanged { _ in onResize(.drag(edge: edge)) }
                    .onEnded { _ in onResize(.end) }
            )
            .onTapGesture(count: 2) { onResize(.reset) }
            // If the island collapses mid-drag the gesture is cancelled without onEnded; end the resize anyway.
            .onDisappear { onResize(.end) }
    }

    /// The indicator hangs off the island's right or left top corner.
    private var indicatorAlignment: Alignment {
        if case .rest(_, let indicator?, _) = presentation.content, indicator.side == .left { .topLeading } else { .topTrailing }
    }

    /// Turned-on plugins with something to show, in display order.
    private var sections: [any NocciPlugin] {
        settings.activePlugins.compactMap { plugins[$0] }.filter(\.hasContent)
    }

    @ViewBuilder
    private func contentView(_ content: PanelPresentation.Content) -> some View {
        switch content {
        case .alert(let item, let scrolls, _, let stacked):
            AlertCard(item: item, notchHeight: presentation.notchHeight, scrolls: scrolls)
                // The whole card, not just its text: click opens the app (or the list, for a stack), swipe up
                // dismisses.
                .contentShape(Rectangle())
                .onTapGesture { if stacked > 0 { actions.openList() } else { actions.open(item) } }
                .swipeToDismiss(item.id, axis: .vertical, tracker: swipeTracker)
        case .rest(_, _, let compactID):
            if let compactID, let plugin = plugins[compactID] {
                // Compact views in the wings beside the notch.
                HStack(spacing: 0) {
                    plugin.makeCompactLeading().frame(width: compactWingWidth)
                    Spacer(minLength: 0)
                    plugin.makeCompactTrailing().frame(width: compactWingWidth)
                }
                .frame(height: presentation.notchHeight)
            }
        case .expanded:
            // Always scrollable: sections can grow while it's open (new notifications), past what was measured.
            ExpandedView(plugins: sections, notchHeight: presentation.notchHeight, scrolls: true)
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
