import AppKit
import ApplicationServices

/// A system media key.
enum MediaKey: Int {
    case playPause = 16
    case next = 17
    case previous = 18
}

/// Posts media-key events so Nocci can control whatever app owns Now Playing. Needs Accessibility.
@MainActor
final class MediaKeys {
    private var hasPrompted = false

    /// Whether Nocci is trusted for Accessibility (no prompt).
    var isTrusted: Bool {
        AXIsProcessTrustedWithOptions(["AXTrustedCheckOptionPrompt": false] as CFDictionary)
    }

    /// Posts a key press. Returns false, posting nothing, if Accessibility isn't granted; the system
    /// prompt is shown only the first time.
    @discardableResult
    func send(_ key: MediaKey) -> Bool {
        guard isTrusted else {
            if !hasPrompted {
                hasPrompted = true
                _ = AXIsProcessTrustedWithOptions(["AXTrustedCheckOptionPrompt": true] as CFDictionary)
            }
            return false
        }
        post(key, down: true)
        post(key, down: false)
        return true
    }

    private func post(_ key: MediaKey, down: Bool) {
        let flags = NSEvent.ModifierFlags(rawValue: down ? 0xA00 : 0xB00)
        let data1 = (key.rawValue << 16) | ((down ? 0xA : 0xB) << 8)
        let event = NSEvent.otherEvent(
            with: .systemDefined,
            location: .zero,
            modifierFlags: flags,
            timestamp: 0,
            windowNumber: 0,
            context: nil,
            subtype: 8,
            data1: data1,
            data2: -1)
        event?.cgEvent?.post(tap: .cghidEventTap)
    }
}
