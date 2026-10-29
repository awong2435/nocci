import AppKit

/// Detects whether a full-screen app owns a screen, by checking whether that screen's menu bar is showing.
///
/// A maximized window covers the same area as a full-screen one on a notched Mac, so window sizes can't tell
/// them apart; the menu bar window can. Uses window bounds only, which need no permission.
/// Caveat: with "Automatically hide and show the menu bar" set to Always, this reports full screen everywhere.
enum FullScreenDetector {
    static func isFullScreenAppShowing(on screen: NSScreen) -> Bool {
        guard let windows = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as? [[String: Any]],
              let primaryHeight = NSScreen.screens.first?.frame.height
        else { return false }

        // Window bounds use a top-left origin measured from the primary screen.
        let screenTop = CGRect(
            x: screen.frame.minX,
            y: primaryHeight - screen.frame.maxY,
            width: screen.frame.width,
            height: 1
        )
        let menuBarLevel = Int(CGWindowLevelForKey(.mainMenuWindow))

        let menuBarShowing = windows.contains { window in
            guard window[kCGWindowLayer as String] as? Int == menuBarLevel,
                  window[kCGWindowOwnerName as String] as? String == "Window Server",
                  let bounds = (window[kCGWindowBounds as String] as? NSDictionary)
                      .flatMap({ CGRect(dictionaryRepresentation: $0 as CFDictionary) })
            else { return false }
            return bounds.intersects(screenTop)
        }
        return !menuBarShowing
    }
}
