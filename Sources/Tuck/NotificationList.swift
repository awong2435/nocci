import SwiftUI
import TuckCore

/// The full list: every visible notification grouped by app, newest first, with full text.
struct NotificationList: View {
    let store: NotificationStore
    /// Height of the notch, or 0 on screens without one. Content starts below it.
    let notchHeight: CGFloat
    /// Wraps the list in a scroll view when it's taller than the panel allows.
    let scrolls: Bool

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
        .background(.black, in: UnevenRoundedRectangle(bottomLeadingRadius: 18, bottomTrailingRadius: 18))
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: 14) {
            if store.items.isEmpty {
                Text("No notifications")
                    .foregroundStyle(.white.opacity(0.5))
                    .frame(maxWidth: .infinity)
            }
            ForEach(store.groupedByApp) { group in
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 6) {
                        if let icon = AppInfo.icon(for: group.appBundleID) {
                            Image(nsImage: icon).resizable().frame(width: 16, height: 16)
                        }
                        Text(group.appName).fontWeight(.semibold)
                        Text("\(group.items.count)")
                    }
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.6))

                    ForEach(group.items) { item in
                        NotificationRow(item: item)
                    }
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 16)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// Height the list needs at `width` to show everything without scrolling.
    @MainActor
    static func naturalHeight(of store: NotificationStore, width: CGFloat, notchHeight: CGFloat) -> CGFloat {
        let probe = NSHostingView(rootView: NotificationList(store: store, notchHeight: notchHeight, scrolls: false).frame(width: width))
        return probe.fittingSize.height
    }
}

private struct NotificationRow: View {
    let item: NotificationItem

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(alignment: .firstTextBaseline) {
                Text(item.title)
                    .font(.subheadline.weight(.semibold))
                    .fixedSize(horizontal: false, vertical: true)
                Spacer()
                Text(timestamp)
                    .font(.caption2)
                    .foregroundStyle(.white.opacity(0.5))
            }
            if let subtitle = item.subtitle {
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.75))
                    .fixedSize(horizontal: false, vertical: true)
            }
            if !item.body.isEmpty {
                Text(item.body)
                    .font(.callout)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .foregroundStyle(.white)
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
    }

    /// Time for today's notifications, otherwise the date and time.
    private var timestamp: String {
        Calendar.current.isDateInToday(item.date)
            ? item.date.formatted(date: .omitted, time: .shortened)
            : item.date.formatted(.dateTime.month(.abbreviated).day().hour().minute())
    }
}
