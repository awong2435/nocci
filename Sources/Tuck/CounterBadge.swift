import SwiftUI
import TuckCore

/// Unread badge that extends the notch sideways: the newest unread app's icon on the left, the count on the right.
/// On screens without a notch it's a small pill.
struct CounterBadge: View {
    /// Width each side extends past the notch.
    static let wingWidth: CGFloat = 40
    /// Height on screens without a notch.
    static let pillHeight: CGFloat = 24

    let count: Int
    let newestAppBundleID: String?
    let notchWidth: CGFloat

    var body: some View {
        HStack(spacing: 0) {
            Group {
                if let bundleID = newestAppBundleID, let icon = AppInfo.icon(for: bundleID) {
                    Image(nsImage: icon).resizable().frame(width: 16, height: 16)
                }
            }
            .frame(width: Self.wingWidth)

            Spacer(minLength: notchWidth)

            Text(count > 99 ? "99+" : "\(count)")
                .font(.system(size: 12, weight: .semibold).monospacedDigit())
                .foregroundStyle(.white)
                .contentTransition(.numericText())
                .frame(width: Self.wingWidth)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.black, in: UnevenRoundedRectangle(bottomLeadingRadius: 10, bottomTrailingRadius: 10))
    }
}
