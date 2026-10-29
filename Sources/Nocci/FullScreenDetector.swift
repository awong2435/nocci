import AppKit

/// Detects whether a full-screen app owns a screen.
///
/// Every regular space shows that screen's wallpaper (a Dock-owned window covering the whole screen, listed as
/// on screen even when other windows hide it); a full-screen app's space doesn't. Window sizes alone can't tell,
/// since a maximized window covers the same area as a full-screen one on a notched Mac, and the menu bar window
/// isn't reliable either: macOS drops it from screens you aren't currently using.
/// Uses window bounds and owners only, which need no permission.
enum FullScreenDetector {
    static func isFullScreenAppShowing(on screen: NSScreen) -> Bool {
        guard let windows = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as? [[String: Any]],
              let primaryHeight = NSScreen.screens.first?.frame.height
        else { return false }

        // Window bounds use a top-left origin measured from the primary screen.
        let screenRect = CGRect(
            x: screen.frame.minX,
            y: primaryHeight - screen.frame.maxY,
            width: screen.frame.width,
            height: screen.frame.height
        )

        let wallpaperShowing = windows.contains { window in
            guard window[kCGWindowOwnerName as String] as? String == "Dock",
                  let layer = window[kCGWindowLayer as String] as? Int, layer < 0,
                  let bounds = (window[kCGWindowBounds as String] as? NSDictionary)
                      .flatMap({ CGRect(dictionaryRepresentation: $0 as CFDictionary) })
            else { return false }
            return bounds.integral == screenRect.integral
        }
        return !wallpaperShowing
    }
}
