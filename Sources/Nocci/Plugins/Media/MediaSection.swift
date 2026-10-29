import SwiftUI

/// The expanded Now Playing section, styled after iOS.
struct MediaSection: View {
    let plugin: MediaPlugin

    @Environment(\.nocciFontScale) private var scale
    /// The volume bar takes the progress row's place, like iOS swapping in a control.
    @State private var showVolume = false
    /// Play/pause state for media keys, where the real state can't be read: starts paused, flips on each press.
    @State private var keysPlaying = false

    var body: some View {
        Group {
            if let track = plugin.track {
                trackLayout(track)
            } else {
                idleLayout
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity)
        .fixedSize(horizontal: false, vertical: true)
    }

    // MARK: Layouts

    private func trackLayout(_ track: MediaTrack) -> some View {
        VStack(spacing: 10 * scale) {
            HStack(spacing: 12) {
                // Like iOS: paused artwork dims and settles back a little.
                ArtworkView(image: plugin.artwork, size: 56, radius: 12)
                    .opacity(track.isPlaying ? 1 : 0.45)
                    .scaleEffect(track.isPlaying ? 1 : 0.9)
                    .animation(.spring(duration: 0.35, bounce: 0.2), value: track.isPlaying)
                VStack(alignment: .leading, spacing: 1) {
                    Text(track.title.isEmpty ? track.appName : track.title)
                        .font(.system(size: 15 * scale, weight: .semibold))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                    Text(track.artist.isEmpty ? track.appName : track.artist)
                        .font(.system(size: 15 * scale))
                        .foregroundStyle(Color(white: 0.55))
                        .lineLimit(1)
                }
                Spacer(minLength: 8)
                WaveformView(tint: plugin.tint, isPlaying: track.isPlaying, height: 22 * scale)
            }
            // Tracks that can't seek (other apps) get the volume bar in the timer's place.
            if showVolume || volumeReplacesTimer {
                volumeRow
            } else {
                ProgressRow(plugin: plugin, duration: track.duration, isPlaying: track.isPlaying, scale: scale)
            }
            controls(isPlaying: track.isPlaying, large: true)
            if let message = plugin.message { messageText(message) }
        }
    }

    private var idleLayout: some View {
        VStack(spacing: 4) {
            if showVolume { volumeRow }
            controls(isPlaying: nil, large: false)
            if let app = plugin.connectableApp {
                // macOS only shows its consent dialog when Nocci asks; this is the clear place to ask.
                pillButton("Allow Nocci to control \(app.displayName)") { plugin.connect() }
            } else if let app = plugin.deniedApp {
                pillButton("Turn on \(app.displayName) in Automation settings") { plugin.openAutomationSettings() }
            } else if let message = plugin.message {
                messageText(message)
            } else {
                Text("Media keys")
                    .font(.system(size: 11 * scale))
                    .foregroundStyle(Color(white: 0.5))
            }
        }
    }

    private func pillButton(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 12 * scale, weight: .medium))
                .foregroundStyle(.white)
                .padding(.horizontal, 12)
                .padding(.vertical, 5)
                .background(Color.white.opacity(0.15), in: Capsule())
        }
        .buttonStyle(PressableStyle())
        .padding(.top, 2)
    }

    private func messageText(_ message: String) -> some View {
        Text(message)
            .font(.system(size: 11 * scale))
            .foregroundStyle(Color(white: 0.6))
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)
    }

    // MARK: Controls

    /// Previous, play or pause, next, centered, with the gray speaker at the right like iOS's output button.
    /// The middle button shows pause while playing and play while paused, morphing between them.
    private func controls(isPlaying: Bool?, large: Bool) -> some View {
        let side = (large ? 26 : 18) * scale
        let center = (large ? 34 : 22) * scale
        let playing = isPlaying ?? keysPlaying
        return ZStack {
            HStack(spacing: (large ? 40 : 30) * scale) {
                button("backward.fill", side) { plugin.previous() }
                Button {
                    if isPlaying == nil { keysPlaying.toggle() }
                    plugin.playPause()
                } label: {
                    Image(systemName: playing ? "pause.fill" : "play.fill")
                        .font(.system(size: center))
                        .foregroundStyle(.white)
                        .contentTransition(.symbolEffect(.replace))
                        .animation(.spring(duration: 0.3), value: playing)
                        .frame(minWidth: 44 * scale, minHeight: 30)
                        .contentShape(Rectangle())
                }
                .buttonStyle(PressableStyle())
                button("forward.fill", side) { plugin.next() }
            }
            // No speaker button when the volume bar is already showing in the timer's place.
            if plugin.volume != nil, !volumeReplacesTimer {
                HStack {
                    Spacer()
                    button(showVolume ? "speaker.wave.2.fill" : "speaker.wave.2", 15 * scale, dim: !showVolume) { toggleVolume() }
                }
            }
        }
        .frame(height: (large ? 40 : 30) * scale)
    }

    /// A track that can't seek shows volume instead of the timer, when the output device has a volume.
    private var volumeReplacesTimer: Bool {
        plugin.track != nil && !plugin.canSeek && plugin.volume != nil
    }

    /// Volume in the same thin iOS bar as the progress row, between a quiet and a loud speaker.
    private var volumeRow: some View {
        HStack(spacing: 10) {
            Image(systemName: "speaker.fill")
                .font(.system(size: 11 * scale))
                .foregroundStyle(Color(white: 0.55))
            ThinBar(fraction: Double(plugin.volume ?? 0)) { value in
                plugin.setVolume(Float(value))
            } onEnd: { value in
                plugin.setVolume(Float(value))
            }
            Image(systemName: "speaker.wave.3.fill")
                .font(.system(size: 11 * scale))
                .foregroundStyle(Color(white: 0.55))
        }
    }

    private func toggleVolume() {
        withAnimation(.easeOut(duration: 0.15)) { showVolume.toggle() }
    }

    private func button(_ symbol: String, _ size: CGFloat, dim: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: size))
                .foregroundStyle(dim ? Color(white: 0.6) : .white)
                .frame(minWidth: 30, minHeight: 30)
                .contentShape(Rectangle())
        }
        .buttonStyle(PressableStyle())
    }
}

/// Elapsed time, seek bar, and remaining time.
private struct ProgressRow: View {
    let plugin: MediaPlugin
    let duration: Double
    let isPlaying: Bool
    let scale: CGFloat

    @State private var dragFraction: Double?

    var body: some View {
        TimelineView(.periodic(from: .now, by: 0.5)) { context in
            let live = duration > 0 ? plugin.position(at: context.date) / duration : 0
            let fraction = min(max(dragFraction ?? live, 0), 1)
            HStack(spacing: 10) {
                timeLabel(mediaTimeString(fraction * duration))
                ThinBar(fraction: fraction) { value in
                    dragFraction = value
                } onEnd: { value in
                    plugin.seek(to: value * duration)
                    dragFraction = nil
                }
                .allowsHitTesting(plugin.canSeek)
                timeLabel("−" + mediaTimeString(duration - fraction * duration))
            }
        }
    }

    private func timeLabel(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 11 * scale).monospacedDigit())
            .foregroundStyle(Color(white: 0.6))
            .lineLimit(1)
    }
}
