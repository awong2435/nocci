import SwiftUI

/// Unread indicator: a thin black lip under the notch, exactly the notch's width, with a small green light.
/// On screens without a notch it's a small pill at the top center.
struct CounterBadge: View {
    /// Height of the lip below the notch (or of the whole pill without a notch).
    static let lipHeight: CGFloat = 10
    /// Pill width on screens without a notch.
    static let pillWidth: CGFloat = 36

    var body: some View {
        Circle()
            .fill(.green)
            .frame(width: 6, height: 6)
            .shadow(color: .green.opacity(0.8), radius: 3)
            .padding(.bottom, 2)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
            .background(.black, in: UnevenRoundedRectangle(bottomLeadingRadius: 8, bottomTrailingRadius: 8))
    }
}
