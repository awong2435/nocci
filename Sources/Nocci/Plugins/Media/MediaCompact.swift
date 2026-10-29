import SwiftUI

/// Left of the notch at rest: small artwork.
struct MediaCompactLeading: View {
    let plugin: MediaPlugin

    var body: some View {
        ArtworkView(image: plugin.artwork, size: 22, radius: 5)
            .frame(width: compactWingWidth, height: 38)
    }
}

/// Right of the notch at rest: small waveform in the artwork's tint.
struct MediaCompactTrailing: View {
    let plugin: MediaPlugin

    var body: some View {
        WaveformView(tint: plugin.tint, isPlaying: plugin.isPlaying, height: 16)
            .frame(width: compactWingWidth, height: 38)
    }
}
