import AppKit
import SwiftUI
import TuckCore

/// One notification as a wide black card that hangs from the notch, with the full text.
struct AlertCard: View {
    let item: NotificationItem
    /// Height of the notch, or 0 on screens without one. Content starts below it.
    let notchHeight: CGFloat
    /// Wraps the text in a scroll view when it's taller than the panel allows.
    let scrolls: Bool

    var body: some View {
        Group {
            if scrolls {
                ScrollView { content }
            } else {
                content
            }
        }
        .padding(.top, notchHeight + 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.black, in: UnevenRoundedRectangle(bottomLeadingRadius: 18, bottomTrailingRadius: 18))
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                if let icon = AppInfo.icon(for: item.appBundleID) {
                    Image(nsImage: icon).resizable().frame(width: 16, height: 16)
                }
                Text(item.appName)
                Spacer()
                Text(item.date.formatted(date: .omitted, time: .shortened))
            }
            .font(.caption)
            .foregroundStyle(.white.opacity(0.6))

            Text(item.title)
                .font(.headline)
                .fixedSize(horizontal: false, vertical: true)
            if let subtitle = item.subtitle {
                Text(subtitle)
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.75))
                    .fixedSize(horizontal: false, vertical: true)
            }
            if !item.body.isEmpty {
                Text(item.body)
                    .font(.body)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 20)
        .padding(.bottom, 16)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// Height the card needs at `width` to show everything without scrolling.
    @MainActor
    static func naturalHeight(of item: NotificationItem, width: CGFloat, notchHeight: CGFloat) -> CGFloat {
        let probe = NSHostingView(rootView: AlertCard(item: item, notchHeight: notchHeight, scrolls: false).frame(width: width))
        return probe.fittingSize.height
    }
}
