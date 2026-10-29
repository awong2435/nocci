import SwiftUI

/// A section Nocci can show when the island opens. Plugins are compiled in (Swift files under
/// `Sources/Nocci/Plugins/`), turned on or off and ordered in Settings.
///
/// Plugins must follow CLAUDE.md: no networking, no logging or saving of personal content, and any permission
/// is requested only after the user turns the plugin on.
@MainActor
protocol NocciPlugin: AnyObject {
    /// Stable ID saved in settings. Must appear in `NocciSettings.defaultPluginOrder`.
    var id: String { get }
    /// Name shown in Settings.
    var name: String { get }
    /// SF Symbol shown next to the name in Settings.
    var systemImage: String { get }
    /// Whether the plugin has anything to show right now (media: something is playing). Sections without
    /// content are left out of the island. Observable, so the island updates when it changes.
    var hasContent: Bool { get }
    /// The section shown in the expanded island. It's laid out at the island's content width, with the
    /// user's text size in `\.nocciFontScale`.
    func makeSection() -> AnyView
    /// Whether to show compact views beside the notch while the island is at rest, like the iPhone's compact
    /// Dynamic Island (media: artwork on the left, waveform on the right while playing). Observable.
    var showsCompact: Bool { get }
    /// Left of the notch at rest, inside a `compactWingWidth` × notch-height area. Only used when `showsCompact`.
    func makeCompactLeading() -> AnyView
    /// Right of the notch at rest, same size as the leading view. Only used when `showsCompact`.
    func makeCompactTrailing() -> AnyView
    /// Called when the plugin is turned on or off, and once at launch, to start or stop any work (polling).
    func setActive(_ active: Bool)
}

/// Width of each compact area beside the notch.
let compactWingWidth: CGFloat = 36

extension EnvironmentValues {
    /// Text size multiplier from Settings. Multiply base point sizes by it so alerts, the list, and plugin
    /// sections all scale together.
    @Entry var nocciFontScale: CGFloat = 1
}
