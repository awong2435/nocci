import NocciCore
import SwiftUI

/// Unread indicator beside the notch, near the top: a small green light (like a camera-in-use light) or the count.
struct CounterBadge: View {
    nonisolated static let diameter: CGFloat = 4
    /// Gap between the notch's edge and the indicator.
    nonisolated static let gap: CGFloat = 8
    /// Distance from the top of the screen to the light.
    nonisolated static let topInset: CGFloat = 7
    /// Width of the resting island on screens without a notch.
    nonisolated static let pillWidth: CGFloat = 36

    /// Room the window needs on each side of the notch for the indicator (kept symmetric so the island stays
    /// centered), with space for the light's glow or a two- or three-digit count.
    nonisolated static func sideRoom(for style: IndicatorStyle) -> CGFloat {
        switch style {
        case .light: gap + diameter + 5
        case .count: gap + 26
        case .off: 0
        }
    }

    let style: IndicatorStyle
    let count: Int

    var body: some View {
        switch style {
        case .light:
            Circle()
                .fill(.green)
                .frame(width: Self.diameter, height: Self.diameter)
                .shadow(color: .green.opacity(0.8), radius: 2)
        case .count:
            Text(count > 99 ? "99+" : "\(count)")
                .font(.system(size: 11, weight: .semibold).monospacedDigit())
                .foregroundStyle(.white)
                .contentTransition(.numericText())
        case .off:
            EmptyView()
        }
    }
}
