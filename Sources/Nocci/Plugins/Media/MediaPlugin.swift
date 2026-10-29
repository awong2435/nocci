import AppKit
import Observation
import SwiftUI

/// The track being shown. Memory only; never logged or saved.
struct MediaTrack: Equatable {
    var app: MediaApp
    var title: String
    var artist: String
    var duration: Double
    var isPlaying: Bool
    /// Position in seconds at `asOf`; use `MediaPlugin.position(at:)` for the live value.
    var position: Double
    var asOf: Date
}

/// Now Playing for Apple Music and Spotify, with media-key fallback for other apps.
@MainActor @Observable
final class MediaPlugin: NocciPlugin {
    let id = "media"
    let name = "Media"
    let systemImage = "play.circle"

    private(set) var isActive = false
    /// The current track from Music or Spotify, or nil (then the section shows media keys only).
    private(set) var track: MediaTrack?
    /// Music artwork for the current track; nil for Spotify or when unavailable (placeholder).
    private(set) var artwork: NSImage?
    /// Waveform color from the artwork; gray without artwork.
    private(set) var tint: Color = ArtworkTint.fallback
    /// System output volume 0...1, or nil if the output device has none.
    private(set) var volume: Float?
    /// Inline permission hint (Automation or Accessibility), or nil.
    var message: String? { controlNote ?? automationNote }
    /// Whether a track is showing. Changes only when that flips (unlike `track`, which updates every poll),
    /// so the island re-measures only when the section's layout actually changes.
    private(set) var hasTrack = false
    /// Whether the shown track is playing. Changes only when that flips.
    private(set) var isPlaying = false

    private var controlNote: String?
    private var automationNote: String?

    @ObservationIgnored private let client = NowPlayingClient()
    @ObservationIgnored private let mediaKeys = MediaKeys()
    @ObservationIgnored private let systemVolume = SystemVolume()
    @ObservationIgnored private var pollTask: Task<Void, Never>?
    @ObservationIgnored private var noteTask: Task<Void, Never>?
    @ObservationIgnored private var artworkCache: [String: (image: NSImage?, tint: Color)] = [:]
    @ObservationIgnored private var artworkOrder: [String] = []
    @ObservationIgnored private var artworkKey: String?
    /// Skips a poll while the previous one is still waiting on an app.
    @ObservationIgnored private var isPolling = false

    var hasContent: Bool { isActive }
    var showsCompact: Bool { isActive && isPlaying }

    func setActive(_ active: Bool) {
        guard active != isActive else { return }
        isActive = active
        if active {
            volume = systemVolume.current()
            systemVolume.onChange = { [weak self] value in self?.volume = value }
            systemVolume.start()
            pollTask = Task { [weak self] in
                while !Task.isCancelled {
                    await self?.poll()
                    try? await Task.sleep(for: .seconds(1))
                }
            }
        } else {
            pollTask?.cancel()
            pollTask = nil
            noteTask?.cancel()
            noteTask = nil
            systemVolume.stop()
            setTrack(nil)
            artwork = nil
            tint = ArtworkTint.fallback
            volume = nil
            controlNote = nil
            automationNote = nil
            artworkCache = [:]
            artworkOrder = []
            artworkKey = nil
        }
    }

    #if DEBUG
    /// A made-up track so the views can be rendered (`--render-media`) without a player or any permission.
    func loadSample(playing: Bool) {
        isActive = true
        setTrack(MediaTrack(app: .music, title: "The Title Track", artist: "Origami Angel", duration: 151,
                            isPlaying: playing, position: 133, asOf: .now))
        tint = Color(red: 0.55, green: 0.68, blue: 0.45)
    }
    #endif

    func makeSection() -> AnyView { AnyView(MediaSection(plugin: self)) }
    func makeCompactLeading() -> AnyView { AnyView(MediaCompactLeading(plugin: self)) }
    func makeCompactTrailing() -> AnyView { AnyView(MediaCompactTrailing(plugin: self)) }

    // MARK: Position

    /// The interpolated playback position in seconds.
    func position(at date: Date) -> Double {
        guard let track else { return 0 }
        guard track.isPlaying else { return track.position }
        let live = track.position + date.timeIntervalSince(track.asOf)
        return track.duration > 0 ? min(live, track.duration) : live
    }

    // MARK: Controls

    /// Plays or pauses.
    func playPause() {
        send(.playPause)
        if var current = track {
            current.position = position(at: .now)
            current.asOf = .now
            current.isPlaying.toggle()
            setTrack(current)
        }
    }

    /// Skips to the next track.
    func next() { send(.next) }

    /// Goes to the previous track.
    func previous() { send(.previous) }

    /// Seeks to a position in seconds.
    func seek(to seconds: Double) {
        guard var current = track else { return }
        let target = min(max(seconds, 0), current.duration)
        current.position = target
        current.asOf = .now
        setTrack(current)
        Task {
            if let code = await client.seek(to: target, in: current.app) {
                reportControlError(code, app: current.app)
            }
        }
    }

    /// Sets the system output volume (0...1).
    func setVolume(_ value: Float) {
        systemVolume.set(value)
        volume = min(max(value, 0), 1)
    }

    /// Sends to the app whose track is showing. With no track, a press is the moment to ask for Automation
    /// permission for a running Music or Spotify that hasn't been asked yet; otherwise it falls back to media keys.
    private func send(_ command: MediaCommand) {
        Task {
            var app = track?.app
            if app == nil {
                for candidate in MediaApp.allCases where await client.permission(for: candidate, ask: false) == .notAsked {
                    if await client.permission(for: candidate, ask: true) == .granted { app = candidate }
                    break
                }
            }
            if let app {
                if let code = await client.send(command, to: app) {
                    reportControlError(code, app: app)
                } else {
                    setControlNote(nil)
                    refreshSoon()
                }
            } else if mediaKeys.send(command.key) {
                setControlNote(nil)
                refreshSoon()
            } else {
                setControlNote("Allow Nocci in System Settings › Privacy & Security › Accessibility to control other apps.")
            }
        }
    }

    private func reportControlError(_ code: Int, app: MediaApp) {
        if code == NowPlayingClient.notAuthorized {
            setControlNote(Self.automationMessage(app))
        }
    }

    private func setControlNote(_ note: String?) {
        controlNote = note
        noteTask?.cancel()
        guard note != nil else { return }
        noteTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(8))
            guard !Task.isCancelled else { return }
            self?.controlNote = nil
        }
    }

    private func refreshSoon() {
        Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(400))
            await self?.poll()
        }
    }

    private static func automationMessage(_ app: MediaApp) -> String {
        "Allow Nocci to control \(app.displayName) in System Settings › Privacy & Security › Automation."
    }

    // MARK: Polling

    /// Reads Music and Spotify, but only ones that are running and that the user has already allowed Nocci to
    /// control, so polling never brings up a permission dialog. Asking happens on a control press (see `send`).
    private func poll() async {
        guard isActive, !isPolling else { return }
        isPolling = true
        defer { isPolling = false }

        var playing: (MediaApp, NowPlayingSnapshot)?
        var paused: (MediaApp, NowPlayingSnapshot)?
        var deniedApp: MediaApp?
        for app in MediaApp.allCases {
            switch await client.permission(for: app, ask: false) {
            case .granted:
                break
            case .denied:
                deniedApp = deniedApp ?? app
                continue
            case .notAsked, .notRunning:
                continue
            }
            switch await client.poll(app) {
            case .track(let snapshot):
                if snapshot.isPlaying {
                    if playing == nil { playing = (app, snapshot) }
                } else if paused == nil {
                    paused = (app, snapshot)
                }
            case .denied:
                deniedApp = deniedApp ?? app
            case .idle, .failed:
                break
            }
        }
        guard isActive else { return }
        guard let (app, snapshot) = playing ?? paused else {
            setTrack(nil)
            await showArtwork(key: nil, app: nil)
            setAutomationNote(deniedApp.map(Self.automationMessage))
            return
        }
        setAutomationNote(nil)
        let new = MediaTrack(app: app, title: snapshot.title, artist: snapshot.artist,
                             duration: snapshot.duration, isPlaying: snapshot.isPlaying,
                             position: snapshot.position, asOf: .now)
        setTrack(new)
        await showArtwork(key: "\(app.bundleID)|\(new.title)|\(new.artist)|\(Int(new.duration))", app: app)
    }

    /// Updates the track, and the layout flags only when they actually change.
    private func setTrack(_ new: MediaTrack?) {
        track = new
        if hasTrack != (new != nil) { hasTrack = new != nil }
        if isPlaying != (new?.isPlaying ?? false) { isPlaying = new?.isPlaying ?? false }
    }

    private func setAutomationNote(_ note: String?) {
        if automationNote != note { automationNote = note }
    }

    /// Loads artwork once per track (Music only) and derives the tint.
    private func showArtwork(key: String?, app: MediaApp?) async {
        guard key != artworkKey else { return }
        artworkKey = key
        guard let key, let app else {
            artwork = nil
            tint = ArtworkTint.fallback
            return
        }
        if let cached = artworkCache[key] {
            artwork = cached.image
            tint = cached.tint
            return
        }
        var image: NSImage?
        if app == .music, let data = await client.musicArtworkData() {
            image = NSImage(data: data)
        }
        let color = ArtworkTint.color(for: image)
        artworkCache[key] = (image, color)
        artworkOrder.append(key)
        if artworkOrder.count > 8 {
            artworkCache[artworkOrder.removeFirst()] = nil
        }
        artwork = image
        tint = color
    }
}
