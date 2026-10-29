import AppKit
import SwiftUI

/// Album artwork, or a gray placeholder with a music note.
struct ArtworkView: View {
    let image: NSImage?
    let size: CGFloat
    let radius: CGFloat

    var body: some View {
        Group {
            if let image {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                ZStack {
                    Color(white: 0.2)
                    Image(systemName: "music.note")
                        .font(.system(size: size * 0.42, weight: .medium))
                        .foregroundStyle(Color(white: 0.5))
                }
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
    }
}

/// Animated equalizer bars in the artwork's color. Like iOS, they settle into a row of still dots when paused.
struct WaveformView: View {
    let tint: Color
    let isPlaying: Bool
    let height: CGFloat

    private let barCount = 6

    var body: some View {
        if isPlaying {
            TimelineView(.animation(minimumInterval: 1.0 / 20)) { context in
                bars(time: context.date.timeIntervalSinceReferenceDate)
            }
        } else {
            bars(time: nil)
        }
    }

    private func bars(time: Double?) -> some View {
        HStack(spacing: height * 0.12) {
            ForEach(0..<barCount, id: \.self) { index in
                Capsule()
                    .fill(time == nil ? tint.opacity(0.5) : tint)
                    .frame(width: height * 0.14, height: max(height * level(index, time), height * 0.14))
            }
        }
        .frame(height: height)
        .animation(.easeOut(duration: 0.25), value: time == nil)
    }

    private func level(_ index: Int, _ time: Double?) -> Double {
        // Paused: dots (the minimum height equals the bar width).
        guard let time else { return 0 }
        let phase = Double(index) * 1.3
        let a = sin(time * (4.2 + Double(index) * 0.7) + phase)
        let b = sin(time * (2.3 + Double(index) * 0.4) + phase * 2)
        return 0.3 + 0.7 * abs(a * 0.6 + b * 0.4)
    }
}

/// A thin rounded bar that can be dragged or tapped. Used for progress and volume.
struct ThinBar: View {
    /// Fill amount, 0...1.
    let fraction: Double
    /// Called on every drag update.
    var onChange: (Double) -> Void = { _ in }
    /// Called when the drag or tap ends.
    var onEnd: (Double) -> Void = { _ in }

    @State private var isDragging = false

    var body: some View {
        GeometryReader { proxy in
            let width = max(proxy.size.width, 1)
            // iOS: a thin gray bar on a dark track that thickens while dragged.
            let thickness: CGFloat = isDragging ? 9 : 5
            ZStack(alignment: .leading) {
                Rectangle().fill(Color.white.opacity(0.18))
                Rectangle().fill(Color.white.opacity(isDragging ? 0.9 : 0.6))
                    .frame(width: width * min(max(fraction, 0), 1))
            }
            .clipShape(Capsule())
            .frame(height: thickness)
            .frame(maxHeight: .infinity)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        isDragging = true
                        onChange(min(max(value.location.x / width, 0), 1))
                    }
                    .onEnded { value in
                        isDragging = false
                        onEnd(min(max(value.location.x / width, 0), 1))
                    }
            )
            .animation(.easeOut(duration: 0.12), value: isDragging)
        }
        .frame(height: 18)
    }
}

/// Shrinks slightly while pressed.
struct PressableStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .opacity(configuration.isPressed ? 0.6 : 1)
            .scaleEffect(configuration.isPressed ? 0.92 : 1)
            .animation(.easeOut(duration: 0.1), value: configuration.isPressed)
    }
}

/// Formats seconds as m:ss, or h:mm:ss from an hour up.
func mediaTimeString(_ seconds: Double) -> String {
    let total = max(Int(seconds.rounded(.down)), 0)
    let h = total / 3600, m = (total % 3600) / 60, s = total % 60
    return h > 0 ? String(format: "%d:%02d:%02d", h, m, s) : String(format: "%d:%02d", m, s)
}
