import AppKit
import Foundation

/// An app Nocci can read and control over AppleScript.
enum MediaApp: CaseIterable, Sendable {
    case music
    case spotify

    var bundleID: String {
        switch self {
        case .music: "com.apple.Music"
        case .spotify: "com.spotify.client"
        }
    }

    var displayName: String {
        switch self {
        case .music: "Music"
        case .spotify: "Spotify"
        }
    }
}

/// A transport command.
enum MediaCommand: Sendable {
    case playPause
    case next
    case previous

    var key: MediaKey {
        switch self {
        case .playPause: .playPause
        case .next: .next
        case .previous: .previous
        }
    }

    fileprivate var script: String {
        switch self {
        case .playPause: "playpause"
        case .next: "next track"
        case .previous: "previous track"
        }
    }
}

/// What the player reported at one poll. Memory only; never logged or saved.
struct NowPlayingSnapshot: Sendable {
    var title: String
    var artist: String
    var duration: Double
    var position: Double
    var isPlaying: Bool
}

/// Outcome of polling one app.
enum NowPlayingPoll: Sendable {
    case track(NowPlayingSnapshot)
    case idle
    case denied
    case failed
}

/// Whether Nocci may send Apple Events to an app.
enum AutomationPermission: Sendable {
    case granted
    /// Never asked; asking shows the macOS consent dialog.
    case notAsked
    case denied
    case notRunning
}

/// Talks to Music and Spotify with NSAppleScript on its own serial queue, so a hung player or a permission
/// dialog never blocks the main thread. Every script runs only `if application id … is running`, with a
/// 2-second timeout, so it can never launch or relaunch the app.
final class NowPlayingClient: @unchecked Sendable {
    /// AppleScript's "not authorized to send Apple events" error.
    static let notAuthorized = -1743

    /// Serial queue that owns `scripts` and runs every Apple Event.
    private let queue = DispatchQueue(label: "local.nocci.now-playing")
    private var scripts: [String: NSAppleScript] = [:]

    /// Whether the app is already running.
    static func isRunning(_ app: MediaApp) -> Bool {
        !NSRunningApplication.runningApplications(withBundleIdentifier: app.bundleID).isEmpty
    }

    /// Whether Nocci may control `app`. With `ask`, shows the macOS consent dialog if the user hasn't answered
    /// yet; only call that from a user action (pressing a control).
    func permission(for app: MediaApp, ask: Bool) async -> AutomationPermission {
        await onQueue {
            guard Self.isRunning(app) else { return .notRunning }
            var target = AEAddressDesc()
            let created = app.bundleID.withCString { name in
                AECreateDesc(DescType(typeApplicationBundleID), name, strlen(name), &target)
            }
            guard created == noErr else { return .denied }
            defer { AEDisposeDesc(&target) }
            let status = AEDeterminePermissionToAutomateTarget(&target, AEEventClass(typeWildCard), AEEventID(typeWildCard), ask)
            switch status {
            case noErr: return .granted
            case -1744: return .notAsked   // errAEEventWouldRequireUserConsent
            case OSStatus(procNotFound): return .notRunning
            default: return .denied
            }
        }
    }

    /// Reads the player state, track, and position.
    func poll(_ app: MediaApp) async -> NowPlayingPoll {
        let source = Self.pollScript(app)
        return await onQueue { [self] in
            switch run(source, cache: true) {
            case .failure(let code):
                return code == Self.notAuthorized ? .denied : .failed
            case .success(let list):
                guard list.numberOfItems >= 5,
                      let state = list.atIndex(1)?.stringValue, state != "stopped" else { return .idle }
                return .track(NowPlayingSnapshot(
                    title: list.atIndex(2)?.stringValue ?? "",
                    artist: list.atIndex(3)?.stringValue ?? "",
                    duration: Double(list.atIndex(4)?.int32Value ?? 0) / 1000,
                    position: Double(list.atIndex(5)?.int32Value ?? 0) / 1000,
                    isPlaying: state == "playing"))
            }
        }
    }

    /// Sends a transport command. Returns an AppleScript error number, or nil on success.
    func send(_ command: MediaCommand, to app: MediaApp) async -> Int? {
        let source = Self.guarded(app, "tell application id \"\(app.bundleID)\" to \(command.script)")
        return await onQueue { [self] in Self.errorCode(run(source, cache: true)) }
    }

    /// Seeks to a position in seconds. Returns an AppleScript error number, or nil on success.
    func seek(to seconds: Double, in app: MediaApp) async -> Int? {
        let ms = Int(max(seconds, 0) * 1000)
        // The target is part of the source, so don't cache it (every seek would add a script).
        let source = Self.guarded(app, "tell application id \"\(app.bundleID)\" to set player position to (\(ms) / 1000)")
        return await onQueue { [self] in Self.errorCode(run(source, cache: false)) }
    }

    /// Raw artwork bytes of the current Music track. Spotify's would need the network, so it's not offered.
    func musicArtworkData() async -> Data? {
        let source = Self.guarded(.music, """
            tell application id "com.apple.Music"
            	try
            		return data of artwork 1 of current track
            	on error
            		return missing value
            	end try
            end tell
            """)
        return await onQueue { [self] in
            guard case .success(let descriptor) = run(source, cache: true), !descriptor.data.isEmpty else { return nil }
            return descriptor.data
        }
    }

    private enum Outcome {
        case success(NSAppleEventDescriptor)
        case failure(Int)
    }

    private static func errorCode(_ outcome: Outcome) -> Int? {
        if case .failure(let code) = outcome { return code }
        return nil
    }

    private func onQueue<T: Sendable>(_ body: @escaping @Sendable () -> T) async -> T {
        await withCheckedContinuation { continuation in
            queue.async { continuation.resume(returning: body()) }
        }
    }

    /// Runs on `queue` only.
    private func run(_ source: String, cache: Bool) -> Outcome {
        let script: NSAppleScript
        if let cached = scripts[source] {
            script = cached
        } else if let made = NSAppleScript(source: source) {
            if cache { scripts[source] = made }
            script = made
        } else {
            return .failure(0)
        }
        var error: NSDictionary?
        let result = script.executeAndReturnError(&error)
        if let error {
            return .failure((error["NSAppleScriptErrorNumber"] as? Int) ?? 0)
        }
        return .success(result)
    }

    /// Wraps a script so it does nothing unless the app is running (checking `running` never launches it)
    /// and gives up after 2 seconds if the app doesn't answer.
    private static func guarded(_ app: MediaApp, _ body: String) -> String {
        """
        if application id "\(app.bundleID)" is running then
        	with timeout of 2 seconds
        \(body)
        	end timeout
        end if
        """
    }

    /// Returns {state, name, artist, duration ms, position ms}. Rethrows only -1743 so denial is detectable.
    private static func pollScript(_ app: MediaApp) -> String {
        let (durationExpr, positionExpr) = switch app {
        case .music: ("((duration of t) * 1000) as integer", "(player position * 1000) as integer")
        case .spotify: ("(duration of t) as integer", "(player position * 1000) as integer")
        }
        return guarded(app, """
            tell application id "\(app.bundleID)"
            	try
            		set st to player state
            		if st is stopped then return {"stopped", "", "", 0, 0}
            		set t to current track
            		set s to "paused"
            		if st is playing then set s to "playing"
            		return {s, name of t, artist of t, \(durationExpr), \(positionExpr)}
            	on error errMsg number errNum
            		if errNum is -1743 then error errMsg number errNum
            		return {"stopped", "", "", 0, 0}
            	end try
            end tell
            """)
    }
}
