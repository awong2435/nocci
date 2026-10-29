import SwiftUI

/// Unread indicator: a small green light just right of the notch, near the top, like a camera-in-use light.
struct CounterBadge: View {
    nonisolated static let diameter: CGFloat = 4
    /// Gap between the notch's right edge and the light.
    nonisolated static let gap: CGFloat = 8
    /// Distance from the top of the screen to the light.
    nonisolated static let topInset: CGFloat = 7
    /// Room the window needs on each side of the notch to fit the light (kept symmetric so the island stays centered), with space for the glow.
    nonisolated static let sideRoom: CGFloat = gap + diameter + 5
    /// Width of the resting island on screens without a notch.
    nonisolated static let pillWidth: CGFloat = 36

    var body: some View {
        Circle()
            .fill(.green)
            .frame(width: Self.diameter, height: Self.diameter)
            .shadow(color: .green.opacity(0.8), radius: 2)
    }
}
