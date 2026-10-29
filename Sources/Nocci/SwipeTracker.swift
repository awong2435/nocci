import AppKit
import NocciCore
import SwiftUI

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

    /// Called once an item has been swiped far enough to dismiss.
    @ObservationIgnored var onDismiss: (NotificationItem.ID) -> Void = { _ in }
    /// Frames of swipeable items in the panel's content view (top-left origin), and their swipe direction.
    @ObservationIgnored private var targets: [NotificationItem.ID: (frame: CGRect, axis: Axis)] = [:]
    /// The item a trackpad swipe started on, for the rest of that gesture.
    @ObservationIgnored private var active: (id: NotificationItem.ID, axis: Axis)?

    /// Points past which a release dismisses.
    private static let dismissDistance: [Axis: CGFloat] = [.horizontal: 70, .vertical: 40]

    func register(_ id: NotificationItem.ID, frame: CGRect, axis: Axis) {
        targets[id] = (frame, axis)
    }

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
            guard let (id, target) = targets.first(where: { $0.value.frame.contains(point) }) else { return false }
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
                self?.onDismiss(id)
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
struct NotificationActions {
    var open: (NotificationItem) -> Void = { _ in }
    /// Dismisses notifications (Clear All, or one app's group).
    var dismiss: ([NotificationItem.ID]) -> Void = { _ in }
}

extension EnvironmentValues {
    /// Swipe tracking for the panel; nil when rendering offscreen (measuring).
    @Entry var swipeTracker: SwipeTracker? = nil
    @Entry var notificationActions = NotificationActions()
}
