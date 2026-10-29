import AppKit
import Observation
import SwiftUI

/// The track being shown. Memory only; never logged or saved.
struct MediaTrack: Equatable {
    /// Music or Spotify, read and controlled over AppleScript; nil for any other app (system Now Playing),
    /// which is controlled with media keys and can't seek.
    var app: MediaApp?
    var bundleID: String
    var appName: String
    var title: String
    var artist: String
    var duration: Double
    var isPlaying: Bool
    /// Position in seconds at `asOf`; use `MediaPlugin.position(at:)` for the live value.
    var position: Double
    var asOf: Date
}

/// Now Playing: Apple Music and Spotify over AppleScript (with artwork and seeking), and any other app (YouTube in
/// a browser, podcasts) through macOS's system Now Playing, controlled with media keys.
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
    /// A running Music or Spotify that Nocci hasn't asked to control yet; the section offers a button to ask.
    private(set) var connectableApp: MediaApp?
    /// A running Music or Spotify the user said no to; the section links to Automation settings.
    private(set) var deniedApp: MediaApp?

    private var controlNote: String?
    private var automationNote: String?

    @ObservationIgnored private let client = NowPlayingClient()
    @ObservationIgnored private let systemNowPlaying = SystemNowPlaying()
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
    /// Seeking works only for Music and Spotify, and only with a known duration.
    var canSeek: Bool { track?.app != nil && (track?.duration ?? 0) > 0 }
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
            connectableApp = nil
            deniedApp = nil
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
        setTrack(MediaTrack(app: .music, bundleID: MediaApp.music.bundleID, appName: "Music", title: "The Title Track", artist: "Origami Angel", duration: 151,
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
        guard var current = track, let app = current.app else { return }
        let target = min(max(seconds, 0), current.duration)
        current.position = target
        current.asOf = .now
        setTrack(current)
        Task {
            if let code = await client.seek(to: target, in: app) {
                reportControlError(code, app: app)
            }
        }
    }

    /// Asks macOS for permission to control `connectableApp` (the consent dialog), then reads it right away.
    func connect() {
        guard let app = connectableApp else { return }
        Task {
            _ = await client.permission(for: app, ask: true)
            await poll()
        }
    }

    /// Opens System Settings › Privacy & Security › Automation, where a "no" can be changed.
    func openAutomationSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Automation") {
            NSWorkspace.shared.open(url)
        }
    }

    /// Sets the system output volume (0...1).
    func setVolume(_ value: Float) {
        systemVolume.set(value)
        volume = min(max(value, 0), 1)
    }

    /// Sends to Music or Spotify when its track is showing. With no track at all, a press is the moment to ask
    /// for Automation permission for a running Music or Spotify that hasn't been asked yet. Anything else (another
    /// app's track, or nothing to ask) uses media keys.
    private func send(_ command: MediaCommand) {
        Task {
            var app = track?.app
            if track == nil {
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
        var connectableApp: MediaApp?
        for app in MediaApp.allCases {
            switch await client.permission(for: app, ask: false) {
            case .granted:
                break
            case .denied:
                deniedApp = deniedApp ?? app
                continue
            case .notAsked:
                connectableApp = connectableApp ?? app
                continue
            case .notRunning:
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
        // Anything else playing (or Music/Spotify without permission), from the system's Now Playing. Skipped
        // while Music or Spotify is playing, since that's what would be shown anyway.
        var system: SystemNowPlaying.Info?
        if playing == nil, let info = await systemNowPlaying.read(), !info.title.isEmpty {
            let scriptedTrack = [paused?.0].compactMap { $0 }.contains { $0.bundleID == info.bundleID }
            if !scriptedTrack { system = info }
        }

        guard isActive else { return }
        if self.connectableApp != connectableApp { self.connectableApp = connectableApp }
        if self.deniedApp != deniedApp { self.deniedApp = deniedApp }

        // A playing track beats a paused one; Music/Spotify (artwork, seeking) beat other apps.
        if let (app, snapshot) = playing ?? (system?.isPlaying == true ? nil : paused) {
            setAutomationNote(nil)
            let new = MediaTrack(app: app, bundleID: app.bundleID, appName: app.displayName,
                                 title: snapshot.title, artist: snapshot.artist,
                                 duration: snapshot.duration, isPlaying: snapshot.isPlaying,
                                 position: snapshot.position, asOf: .now)
            setTrack(new)
            await showArtwork(key: "\(app.bundleID)|\(new.title)|\(new.artist)|\(Int(new.duration))", app: app, url: snapshot.artworkURL)
        } else if let system {
            setAutomationNote(nil)
            let new = MediaTrack(app: nil, bundleID: system.bundleID, appName: AppInfo.name(for: system.bundleID),
                                 title: system.title, artist: system.artist,
                                 duration: system.duration, isPlaying: system.isPlaying,
                                 position: system.position, asOf: .now)
            setTrack(new)
            await showArtwork(key: "\(system.bundleID)|\(new.title)|\(new.artist)", app: nil, url: nil, iconOf: system.bundleID)
        } else {
            setTrack(nil)
            await showArtwork(key: nil, app: nil, url: nil)
            setAutomationNote(deniedApp.map(Self.automationMessage))
        }
    }

    /// Updates the track, and the layout flags only when they actually change.
    private func setTrack(_ new: MediaTrack?) {
        track = new
        if hasTrack != (new != nil) { hasTrack = new != nil }
        if isPlaying != (new?.isPlaying ?? false) { isPlaying = new?.isPlaying ?? false }
    }

    /// Downloads a Spotify cover image. The only network use in Nocci: an image request to Spotify's own image
    /// server (https, `*.scdn.co`), with no cookies, cache, or other data sent, and no notification content ever
    /// involved. Anything else is refused.
    private static func downloadSpotifyArtwork(_ url: URL) async -> Data? {
        guard url.scheme == "https", let host = url.host(), host == "scdn.co" || host.hasSuffix(".scdn.co") else { return nil }
        let configuration = URLSessionConfiguration.ephemeral
        configuration.httpShouldSetCookies = false
        configuration.urlCache = nil
        configuration.timeoutIntervalForRequest = 10
        let session = URLSession(configuration: configuration)
        defer { session.finishTasksAndInvalidate() }
        guard let (data, response) = try? await session.data(from: url),
              (response as? HTTPURLResponse)?.statusCode == 200,
              data.count < 5_000_000 else { return nil }
        return data
    }

    private func setAutomationNote(_ note: String?) {
        if automationNote != note { automationNote = note }
    }

    /// Loads artwork once per track and derives the tint: Music's from the app, Spotify's from Spotify's image
    /// server, and for other apps the app's own icon (`iconOf`), since system Now Playing carries no artwork here.
    private func showArtwork(key: String?, app: MediaApp?, url: URL?, iconOf bundleID: String? = nil) async {
        guard key != artworkKey else { return }
        artworkKey = key
        guard let key, app != nil || bundleID != nil else {
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
        switch app {
        case .music:
            if let data = await client.musicArtworkData() { image = NSImage(data: data) }
        case .spotify:
            if let url, let data = await Self.downloadSpotifyArtwork(url) { image = NSImage(data: data) }
        case nil:
            image = bundleID.flatMap(AppInfo.icon(for:))
        }
        // A newer track may have started while this one's artwork was loading.
        guard artworkKey == key else { return }
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
