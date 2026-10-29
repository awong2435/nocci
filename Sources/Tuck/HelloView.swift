import SwiftUI

/// M1 placeholder: a black shape that wraps the notch with "Hello" below it.
struct HelloView: View {
    /// Height of the notch, or 0 on screens without one.
    let notchHeight: CGFloat

    var body: some View {
        VStack(spacing: 0) {
            Color.clear.frame(height: notchHeight)
            Text("Hello")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(.black, in: UnevenRoundedRectangle(bottomLeadingRadius: 12, bottomTrailingRadius: 12))
    }
}
