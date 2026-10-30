import AppKit
import NocciCore
import OSLog
import SwiftUI

private let log = Logger(subsystem: "local.nocci", category: "swipe")

/// Swipe to dismiss, for both input styles: two-finger trackpad swipes (scroll events with phases, fed in by the
/// panel's scroll monitor) and click-dragging. Alerts swipe up; list rows swipe sideways.
///
/// Swipeable views report their frames, and scroll events are hit-tested against them, rather than relying on
/// hover, which isn't dependable in a panel that never becomes key.
@MainActor
@Observable
final class SwipeTracker {
    /// How far each item is currently pulled: vertical for the alert, horizontal for list rows.
    private(set) var offsets: [NotificationItem.ID: CGFloat] = [:]
    /// The notification under the pointer, for showing its × button. Found from the panel's own mouse tracking
    /// and these frames, since system hover isn't dependable in a panel that never becomes key.
    private(set) var hoveredID: NotificationItem.ID?

    /// Called once an item has been swiped far enough to dismiss.
    @ObservationIgnored var onDismiss: (NotificationItem.ID) -> Void = { _ in }
    /// Called when an alert is swiped up: put it away, but keep the notification (unread, in the list).
    @ObservationIgnored var onHide: (NotificationItem.ID) -> Void = { _ in }
    /// Frames of swipeable items in the panel's content view (top-left origin), and their swipe direction.
    @ObservationIgnored private var targets: [NotificationItem.ID: (frame: CGRect, axis: Axis)] = [:]
    /// The item a trackpad swipe started on, for the rest of that gesture.
    @ObservationIgnored private var active: (id: NotificationItem.ID, axis: Axis)?

    /// Points past which a release dismisses.
    private static let dismissDistance: [Axis: CGFloat] = [.horizontal: 70, .vertical: 40]

    func register(_ id: NotificationItem.ID, frame: CGRect, axis: Axis) {
        targets[id] = (frame, axis)
    }

    /// Updates `hoveredID` for a pointer position in the panel's content view (top-left origin), or nil when the
    /// pointer isn't over the panel.
    func updateHover(at point: CGPoint?) {
        let id = point.flatMap { point in targets.first { $0.value.frame.contains(point) }?.key }
        if id != hoveredID { hoveredID = id }
    }

    #if DEBUG
    /// For rendered previews (`--render-media`), which have no pointer.
    func previewHover(_ id: NotificationItem.ID?) {
        hoveredID = id
    }
    #endif

    func unregister(_ id: NotificationItem.ID) {
        targets[id] = nil
    }

    func offset(_ id: NotificationItem.ID) -> CGFloat {
        offsets[id] ?? 0
    }

    // MARK: - Trackpad

    /// Handles a scroll event aimed at the panel. Returns true if it was part of a swipe and should be consumed;
    /// anything else (vertical scrolling in the list, momentum) passes through.
    func handleScroll(_ event: NSEvent, in view: NSView) -> Bool {
        switch event.phase {
        case .began:
            active = nil
            let point = view.convert(event.locationInWindow, from: nil)
            let hit = targets.first(where: { $0.value.frame.contains(point) })
            // Diagnostics only: whether a swipe started on a notification, never content.
            log.debug("swipe began, on a notification: \(hit != nil, privacy: .public)")
            guard let (id, target) = hit else { return false }
            let horizontal = abs(event.scrollingDeltaX) > abs(event.scrollingDeltaY)
            guard horizontal == (target.axis == .horizontal) else { return false }
            active = (id, target.axis)
            pull(id, axis: target.axis, by: fingerDelta(event, axis: target.axis))
            return true
        case .changed:
            guard let active else { return false }
            pull(active.id, axis: active.axis, by: fingerDelta(event, axis: active.axis))
            return true
        case .ended, .cancelled:
            guard let active else { return false }
            self.active = nil
            release(active.id, axis: active.axis)
            return true
        default:
            return false
        }
    }

    /// How far the fingers moved along `axis`, positive right or down, whatever the scroll direction setting.
    private func fingerDelta(_ event: NSEvent, axis: Axis) -> CGFloat {
        let delta = axis == .horizontal ? event.scrollingDeltaX : event.scrollingDeltaY
        return event.isDirectionInvertedFromDevice ? delta : -delta
    }

    // MARK: - Mouse

    func dragChanged(_ id: NotificationItem.ID, axis: Axis, translation: CGSize) {
        let amount = axis == .horizontal ? translation.width : translation.height
        offsets[id] = constrained(amount, axis: axis)
    }

    func dragEnded(_ id: NotificationItem.ID, axis: Axis) {
        release(id, axis: axis)
    }

    // MARK: - Shared

    private func pull(_ id: NotificationItem.ID, axis: Axis, by delta: CGFloat) {
        offsets[id] = constrained((offsets[id] ?? 0) + delta, axis: axis)
    }

    /// Alerts only go up; pulling down meets resistance.
    private func constrained(_ value: CGFloat, axis: Axis) -> CGFloat {
        axis == .vertical && value > 0 ? value * 0.2 : value
    }

    private func release(_ id: NotificationItem.ID, axis: Axis) {
        let offset = offsets[id] ?? 0
        let dismisses = axis == .horizontal
            ? abs(offset) > Self.dismissDistance[.horizontal]!
            : -offset > Self.dismissDistance[.vertical]!
        if dismisses {
            withAnimation(.easeIn(duration: 0.18)) {
                offsets[id] = axis == .horizontal ? (offset < 0 ? -700 : 700) : -300
            } completion: { [weak self] in
                self?.offsets[id] = nil
                // Sideways (a list row) clears it; up (an alert) only hides it.
                if axis == .horizontal { self?.onDismiss(id) } else { self?.onHide(id) }
            }
        } else {
            withAnimation(.spring(duration: 0.3, bounce: 0.25)) {
                offsets[id] = nil
            }
        }
    }
}

extension View {
    /// Makes this view swipeable to dismiss notification `id`: follows trackpad swipes and click-drags along
    /// `axis`, and fades as it's pulled.
    func swipeToDismiss(_ id: NotificationItem.ID, axis: Axis, tracker: SwipeTracker?) -> some View {
        modifier(SwipeToDismiss(id: id, axis: axis, tracker: tracker))
    }
}

private struct SwipeToDismiss: ViewModifier {
    let id: NotificationItem.ID
    let axis: Axis
    let tracker: SwipeTracker?

    func body(content: Content) -> some View {
        if let tracker {
            let offset = tracker.offset(id)
            content
                .offset(x: axis == .horizontal ? offset : 0, y: axis == .vertical ? offset : 0)
                .opacity(1 - min(abs(offset) / 300, 0.7))
                .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { frame in
                    tracker.register(id, frame: frame, axis: axis)
                }
                .onDisappear { tracker.unregister(id) }
                .simultaneousGesture(
                    DragGesture(minimumDistance: 8)
                        .onChanged { tracker.dragChanged(id, axis: axis, translation: $0.translation) }
                        .onEnded { _ in tracker.dragEnded(id, axis: axis) }
                )
        } else {
            content
        }
    }
}

/// What the list and alert can do with a notification. Supplied by the panel through the environment.
extension View {
    /// A small × at the top-left corner while the pointer is over this notification, like Notification Center's;
    /// clicking it clears the notification (in macOS's Notification Center too).
    /// `offset` places it relative to the top-left corner; the default sits just outside it, as in Notification
    /// Center.
    func clearButtonOnHover(_ id: NotificationItem.ID, offset: CGSize = CGSize(width: -6, height: -6)) -> some View {
        modifier(ClearOnHover(id: id, offset: offset))
    }
}

private struct ClearOnHover: ViewModifier {
    let id: NotificationItem.ID
    let offset: CGSize
    @Environment(\.swipeTracker) private var tracker
    @Environment(\.notificationActions) private var actions
    @Environment(\.nocciFontScale) private var scale

    func body(content: Content) -> some View {
        content.overlay(alignment: .topLeading) {
            if tracker?.hoveredID == id {
                Button { actions.dismiss([id]) } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 8 * scale, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 18 * scale, height: 18 * scale)
                        .background(Color(white: 0.3), in: Circle())
                        .overlay(Circle().stroke(Color.black.opacity(0.5), lineWidth: 1))
                }
                .buttonStyle(.plain)
                .help("Clear")
                .offset(offset)
                .transition(.opacity.combined(with: .scale(scale: 0.6)))
            }
        }
        .animation(.easeOut(duration: 0.12), value: tracker?.hoveredID == id)
    }
}

struct NotificationActions {
    var open: (NotificationItem) -> Void = { _ in }
    /// Opens the full list (clicking a stack of alerts).
    var openList: () -> Void = {}
    /// Dismisses notifications (Clear All, or one app's group).
    var dismiss: ([NotificationItem.ID]) -> Void = { _ in }
}

extension EnvironmentValues {
    /// Swipe tracking for the panel; nil when rendering offscreen (measuring).
    @Entry var swipeTracker: SwipeTracker? = nil
    @Entry var notificationActions = NotificationActions()
}
