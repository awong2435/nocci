import Foundation

/// UserDefaults keys. Settings only; never notification content.
public enum SettingsKey {
    public static let alertDuration = "alertDuration"
    /// Dictionary of display ID (String) to panel width in points.
    public static let panelWidthByDisplay = "panelWidthByDisplay"
    public static let hoverOpenDelay = "hoverOpenDelay"
    public static let hoverCloseDelay = "hoverCloseDelay"
    /// Dictionary of app bundle ID to Bool.
    public static let enabledApps = "enabledApps"

    // State, not settings. The only things Tuck saves about notifications (PLAN.md section 2E).
    /// Date the list was last opened.
    public static let lastOpened = "lastOpened"
    /// Array of dismissed notification IDs.
    public static let dismissedIDs = "dismissedIDs"
}

/// How long an alert stays before collapsing to the counter.
public enum AlertDuration: String, CaseIterable, Sendable {
    case fiveSeconds
    case tenSeconds
    case thirtySeconds
    case untilDismissed

    /// `nil` means the alert stays until dismissed.
    public var seconds: TimeInterval? {
        switch self {
        case .fiveSeconds: 5
        case .tenSeconds: 10
        case .thirtySeconds: 30
        case .untilDismissed: nil
        }
    }
}
