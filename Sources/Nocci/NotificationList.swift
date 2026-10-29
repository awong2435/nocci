import SwiftUI
import NocciCore

/// The full list: every visible notification grouped by app, newest first, with full text.
/// Drawn inside the island shape, which supplies the black background.
struct NotificationList: View {
    let store: NotificationStore
    /// Height of the notch, or 0 on screens without one. Content starts below it.
    let notchHeight: CGFloat
    /// Wraps the list in a scroll view when it's taller than the panel allows.
    let scrolls: Bool
    @Environment(\.nocciFontScale) private var scale

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
        VStack(alignment: .leading, spacing: 14) {
            if store.items.isEmpty {
                Text("No notifications")
                    .font(NocciType.body(scale))
                    .foregroundStyle(.white.opacity(0.5))
                    .frame(maxWidth: .infinity)
            }
            ForEach(store.groupedByApp) { group in
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 6) {
                        if let icon = AppInfo.icon(for: group.appBundleID) {
                            Image(nsImage: icon).resizable().frame(width: NocciType.iconSize(scale), height: NocciType.iconSize(scale))
                        }
                        Text(group.appName).fontWeight(.semibold)
                        Text("\(group.items.count)")
                    }
                    .font(NocciType.meta(scale))
                    .foregroundStyle(.white.opacity(0.6))

                    ForEach(group.items) { item in
                        NotificationRow(item: item)
                            .transition(.opacity.combined(with: .move(edge: .leading)))
                    }
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .animation(.spring(duration: 0.3), value: store.items.map(\.id))
    }

    /// Height the list needs at `width` to show everything without scrolling.
    @MainActor
    static func naturalHeight(of store: NotificationStore, width: CGFloat, notchHeight: CGFloat, fontScale: CGFloat) -> CGFloat {
        let probe = NSHostingView(rootView: NotificationList(store: store, notchHeight: notchHeight, scrolls: false)
            .environment(\.nocciFontScale, fontScale)
            .frame(width: width))
        return probe.fittingSize.height
    }
}

private struct NotificationRow: View {
    let item: NotificationItem
    @Environment(\.nocciFontScale) private var scale
    @Environment(\.swipeTracker) private var swipeTracker
    @Environment(\.notificationActions) private var actions

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(alignment: .firstTextBaseline) {
                Text(item.title)
                    .font(NocciType.title(scale))
                    .fixedSize(horizontal: false, vertical: true)
                Spacer()
                Text(timestamp)
                    .font(NocciType.meta(scale))
                    .foregroundStyle(.white.opacity(0.5))
            }
            if let subtitle = item.subtitle {
                Text(subtitle)
                    .font(NocciType.subtitle(scale))
                    .foregroundStyle(.white.opacity(0.75))
                    .fixedSize(horizontal: false, vertical: true)
            }
            if !item.body.isEmpty {
                Text(item.body)
                    .font(NocciType.body(scale))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .foregroundStyle(.white)
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
        // Click opens the app; swipe sideways dismisses.
        .contentShape(Rectangle())
        .onTapGesture { actions.open(item) }
        .swipeToDismiss(item.id, axis: .horizontal, tracker: swipeTracker)
    }

    /// Time for today's notifications, otherwise the date and time.
    private var timestamp: String {
        Calendar.current.isDateInToday(item.date)
            ? item.date.formatted(date: .omitted, time: .shortened)
            : item.date.formatted(.dateTime.month(.abbreviated).day().hour().minute())
    }
}
