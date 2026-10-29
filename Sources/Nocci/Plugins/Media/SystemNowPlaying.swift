import Foundation

/// macOS's system-wide Now Playing: whatever is playing in any app (YouTube in a browser, podcasts, video).
///
/// Since macOS 15.4, third-party apps can't read the private MediaRemote framework themselves, but Apple's own
/// `/usr/bin/osascript` still can. So this runs a short JavaScript for Automation script in it that reads
/// `MRNowPlayingRequest` and prints JSON. Undocumented: a macOS update may break it, in which case `read()`
/// returns nil and Nocci falls back to Music, Spotify, and media keys. No artwork comes through this way.
/// Results stay in memory; never logged or saved.
struct SystemNowPlaying: Sendable {
    struct Info: Sendable, Equatable {
        var bundleID: String
        var title: String
        var artist: String
        var duration: Double
        /// Position in seconds at the time of the read.
        var position: Double
        var isPlaying: Bool
    }

    /// Reads what's playing, or nil if nothing is, the script fails, or it takes over 3 seconds.
    func read() async -> Info? {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .utility).async {
                continuation.resume(returning: Self.run())
            }
        }
    }

    private static func run() -> Info? {
        guard let scriptURL else { return nil }
        let process = Process()
        process.executableURL = URL(filePath: "/usr/bin/osascript")
        // From a file: passed inline with -e, osascript gets killed (exit 137) when this script loads MediaRemote.
        process.arguments = ["-l", "JavaScript", scriptURL.path]
        let output = Pipe()
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        // Set before starting, or a fast run could finish before anyone is listening.
        let finished = DispatchSemaphore(value: 0)
        process.terminationHandler = { _ in finished.signal() }
        do { try process.run() } catch { return nil }

        if finished.wait(timeout: .now() + 3) == .timedOut {
            process.terminate()
            return nil
        }
        guard process.terminationStatus == 0 else { return nil }

        let data = output.fileHandleForReading.readDataToEndOfFile()
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let bundleID = json["bundleID"] as? String, !bundleID.isEmpty else { return nil }
        let isPlaying = json["playing"] as? Bool ?? false
        var position = json["elapsed"] as? Double ?? 0
        // Elapsed time is as of the timestamp; move it forward to now while playing.
        if isPlaying, let timestamp = json["timestamp"] as? Double {
            position += (Date().timeIntervalSinceReferenceDate - timestamp) * (json["rate"] as? Double ?? 1)
        }
        let duration = json["duration"] as? Double ?? 0
        return Info(
            bundleID: bundleID,
            title: json["title"] as? String ?? "",
            artist: json["artist"] as? String ?? "",
            duration: duration,
            position: duration > 0 ? min(max(position, 0), duration) : max(position, 0),
            isPlaying: isPlaying
        )
    }

    /// The script, written once to Nocci's temporary folder. It holds no personal data.
    private static let scriptURL: URL? = {
        let url = FileManager.default.temporaryDirectory.appending(path: "nocci-now-playing.js")
        do {
            try script.write(to: url, atomically: true, encoding: .utf8)
            return url
        } catch {
            return nil
        }
    }()

    /// Prints {bundleID, title, artist, duration, elapsed, rate, timestamp, playing} as JSON, or "null".
    private static let script = """
        ObjC.import('Foundation');
        $.NSBundle.bundleWithPath('/System/Library/PrivateFrameworks/MediaRemote.framework/').load;
        const Request = $.NSClassFromString('MRNowPlayingRequest');
        const unwrap = v => (v === undefined || v === null || v.isNil()) ? null : ObjC.unwrap(v);
        let out = null;
        if (!Request.isNil()) {
          const item = Request.localNowPlayingItem;
          const path = Request.localNowPlayingPlayerPath;
          if (!item.isNil() && !path.isNil() && !path.client.isNil()) {
            const info = item.nowPlayingInfo;
            const field = name => info.isNil() ? null : info.objectForKey('kMRMediaRemoteNowPlayingInfo' + name);
            const timestamp = field('Timestamp');
            out = {
              bundleID: unwrap(path.client.bundleIdentifier),
              title: unwrap(field('Title')),
              artist: unwrap(field('Artist')),
              duration: unwrap(field('Duration')),
              elapsed: unwrap(field('ElapsedTime')),
              rate: unwrap(field('PlaybackRate')),
              timestamp: (timestamp === null || timestamp.isNil()) ? null : timestamp.timeIntervalSinceReferenceDate,
              playing: Request.localIsPlaying
            };
          }
        }
        JSON.stringify(out);
        """
}
