import NocciCore
import SwiftUI

/// Which app groups are expanded in the list. Shared with the panel so the island re-measures when a group opens.
@MainActor
@Observable
final class NotificationListState {
    var expanded: Set<String> = []
}

/// The full list, laid out like macOS Notification Center: each app's notifications collapse into a stack
/// (the newest card with the rest peeking out behind it); clicking a stack expands it, with Show less and
/// a × that turns into Clear All. Drawn inside the island, which supplies the black background.
struct NotificationList: View {
    let store: NotificationStore
    let state: NotificationListState
    /// Height of the notch, or 0 on screens without one. Content starts below it.
    let notchHeight: CGFloat
    /// Wraps the list in a scroll view when it's taller than the panel allows.
    let scrolls: Bool
    @Environment(\.nocciFontScale) private var scale
    @Environment(\.notificationActions) private var actions
    @Environment(\.nocciSettings) private var settings

    var body: some View {
        Group {
            if scrolls {
                ScrollView { content }
            } else {
                content
            }
        }
        .padding(.top, notchHeight + 8)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Notifications")
                    .font(.system(size: 15 * scale, weight: .semibold))
                Spacer()
                if let settings {
                    QuietButton(settings: settings)
                }
                if !store.items.isEmpty {
                    ClearButton { actions.dismiss(store.items.map(\.id)) }
                }
            }
            .foregroundStyle(.white)

            if store.items.isEmpty {
                Text("No notifications")
                    .font(NocciType.body(scale))
                    .foregroundStyle(.white.opacity(0.5))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
            }
            ForEach(store.groupedByApp) { group in
                if state.expanded.contains(group.id) {
                    expandedGroup(group)
                } else {
                    collapsedGroup(group)
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .animation(.spring(duration: 0.35, bounce: 0.15), value: state.expanded)
        .animation(.spring(duration: 0.3), value: store.items.map(\.id))
    }

    /// The newest card, with up to two more peeking out below it when the app has more.
    private func collapsedGroup(_ group: AppGroup) -> some View {
        let first = group.items[0]
        let layers = min(group.items.count - 1, 2)
        return NotificationCard(item: first) {
            if group.items.count > 1 { state.expanded.insert(group.id) } else { actions.open(first) }
        }
        .background(alignment: .bottom) {
            ZStack(alignment: .bottom) {
                ForEach(Array((0..<layers).reversed()), id: \.self) { index in
                    let level = CGFloat(index + 1)
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(Color(white: 0.13 - 0.025 * level))
                        .frame(height: 24)
                        .padding(.horizontal, 10 * level)
                        .offset(y: 6 * level)
                }
            }
        }
        .padding(.bottom, 6 * CGFloat(layers))
        .transition(.opacity)
    }

    private func expandedGroup(_ group: AppGroup) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Text(group.appName)
                    .font(.system(size: 13 * scale, weight: .semibold))
                    .foregroundStyle(.white)
                Spacer()
                Button { state.expanded.remove(group.id) } label: {
                    Text("Show less")
                        .font(.system(size: 11 * scale, weight: .medium))
                        .foregroundStyle(.white.opacity(0.85))
                        .padding(.horizontal, 10)
                        .frame(height: 22 * scale)
                        .background(.white.opacity(0.14), in: Capsule())
                }
                .buttonStyle(.plain)
                ClearButton { actions.dismiss(group.items.map(\.id)) }
            }
            ForEach(group.items) { item in
                NotificationCard(item: item) { actions.open(item) }
                    .transition(.opacity.combined(with: .move(edge: .leading)))
            }
        }
        .transition(.opacity)
    }

    /// Height the list needs at `width` to show everything without scrolling.
    @MainActor
    static func naturalHeight(of store: NotificationStore, state: NotificationListState, width: CGFloat, notchHeight: CGFloat, fontScale: CGFloat) -> CGFloat {
        let probe = NSHostingView(rootView: NotificationList(store: store, state: state, notchHeight: notchHeight, scrolls: false)
            .environment(\.nocciFontScale, fontScale)
            .frame(width: width))
        return probe.fittingSize.height
    }
}

/// One notification, styled like a Notification Center banner: app icon, title and time, subtitle, body.
/// Click runs `onTap`; swipe sideways dismisses.
private struct NotificationCard: View {
    let item: NotificationItem
    let onTap: () -> Void
    @Environment(\.nocciFontScale) private var scale
    @Environment(\.swipeTracker) private var swipeTracker

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            if let icon = AppInfo.icon(for: item.appBundleID) {
                Image(nsImage: icon)
                    .resizable()
                    .frame(width: 32 * scale, height: 32 * scale)
            }
            VStack(alignment: .leading, spacing: 1) {
                HStack(alignment: .firstTextBaseline) {
                    Text(item.title)
                        .font(NocciType.title(scale))
                        .lineLimit(1)
                    Spacer(minLength: 8)
                    Text(relativeTime(item.date))
                        .font(NocciType.meta(scale))
                        .foregroundStyle(.white.opacity(0.5))
                        .fixedSize()
                }
                if let subtitle = item.subtitle {
                    Text(subtitle)
                        .font(NocciType.title(scale))
                        .fixedSize(horizontal: false, vertical: true)
                }
                if !item.body.isEmpty {
                    Text(item.body)
                        .font(NocciType.body(scale))
                        .foregroundStyle(.white.opacity(0.85))
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .foregroundStyle(.white)
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(white: 0.13), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .onTapGesture(perform: onTap)
        .swipeToDismiss(item.id, axis: .horizontal, tracker: swipeTracker)
        .clearButtonOnHover(item.id)
    }
}

/// Quiet mode toggle: a bell that fills and gets a slash when new notifications should only update the
/// indicator instead of dropping down.
private struct QuietButton: View {
    @Bindable var settings: NocciSettings
    @Environment(\.nocciFontScale) private var scale

    var body: some View {
        Button {
            settings.quietMode.toggle()
        } label: {
            Image(systemName: settings.quietMode ? "bell.slash.fill" : "bell")
                .font(.system(size: 10 * scale, weight: .semibold))
                .contentTransition(.symbolEffect(.replace))
                .frame(width: 22 * scale, height: 22 * scale)
                .foregroundStyle(settings.quietMode ? Color.black : .white.opacity(0.85))
                .background(settings.quietMode ? Color.white.opacity(0.9) : .white.opacity(0.14), in: Circle())
        }
        .buttonStyle(.plain)
        .help(settings.quietMode ? "Quiet mode is on: new notifications only update the light" : "Quiet mode")
        .animation(.spring(duration: 0.25), value: settings.quietMode)
    }
}

/// A round × that turns into a "Clear All" pill on hover (or on the first click, since hover isn't always
/// delivered to a panel that never becomes key); clicking "Clear All" runs `action`.
private struct ClearButton: View {
    let action: () -> Void
    @State private var armed = false
    @Environment(\.nocciFontScale) private var scale

    var body: some View {
        Button {
            if armed { action() } else { armed = true }
        } label: {
            Group {
                if armed {
                    Text("Clear All")
                        .font(.system(size: 11 * scale, weight: .medium))
                        .padding(.horizontal, 10)
                } else {
                    Image(systemName: "xmark")
                        .font(.system(size: 9 * scale, weight: .bold))
                        .frame(width: 22 * scale)
                }
            }
            .frame(height: 22 * scale)
            .foregroundStyle(.white.opacity(0.85))
            .background(.white.opacity(0.14), in: Capsule())
        }
        .buttonStyle(.plain)
        .onHover { armed = $0 }
        .animation(.spring(duration: 0.25), value: armed)
    }
}

/// "now", "16m ago" within the hour, the time today, otherwise the date and time, like Notification Center.
func relativeTime(_ date: Date, now: Date = Date()) -> String {
    let seconds = now.timeIntervalSince(date)
    if seconds < 60 { return "now" }
    if seconds < 3600 { return "\(Int(seconds / 60))m ago" }
    if Calendar.current.isDateInToday(date) { return date.formatted(date: .omitted, time: .shortened) }
    return date.formatted(.dateTime.month(.abbreviated).day().hour().minute())
}
