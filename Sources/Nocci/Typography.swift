import SwiftUI

/// Text sizes shared by alerts and the list, so they always match. Each takes the `\.nocciFontScale` multiplier.
enum NocciType {
    /// App name, group header, and time.
    static func meta(_ scale: CGFloat) -> Font { .system(size: 11 * scale) }
    static func title(_ scale: CGFloat) -> Font { .system(size: 13 * scale, weight: .semibold) }
    static func subtitle(_ scale: CGFloat) -> Font { .system(size: 12 * scale) }
    static func body(_ scale: CGFloat) -> Font { .system(size: 13 * scale) }
    /// App icon size beside the app name.
    static func iconSize(_ scale: CGFloat) -> CGFloat { 16 * scale }
}
