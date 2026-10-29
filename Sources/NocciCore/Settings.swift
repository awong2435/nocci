import Foundation
import Observation

/// UserDefaults keys. Settings only; never notification content.
public enum SettingsKey {
    public static let alertDuration = "alertDuration"
    /// Width of the alert card and list, in points.
    public static let panelWidth = "panelWidth"
    public static let hoverOpenDelay = "hoverOpenDelay"
    public static let hoverCloseDelay = "hoverCloseDelay"
    public static let indicatorStyle = "indicatorStyle"
    public static let indicatorSide = "indicatorSide"
    public static let screenChoice = "screenChoice"
    /// Dictionary of app bundle ID to Bool.
    public static let enabledApps = "enabledApps"

    // State, not settings. The only things Nocci saves about notifications (PLAN.md section 2E).
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

/// How unread notifications are shown beside the notch.
public enum IndicatorStyle: String, CaseIterable, Sendable {
    case light, count, off
}

/// Which side of the notch the indicator sits on.
public enum IndicatorSide: String, CaseIterable, Sendable {
    case left, right
}

/// Which screen Nocci appears on. Screens without a notch get a virtual one at the top center.
public enum ScreenChoice: Hashable, Sendable, RawRepresentable {
    /// The built-in screen with the notch, or the main display if there isn't one.
    case notched
    /// The display with the menu bar.
    case main
    /// Whichever screen the mouse is on.
    case followMouse
    /// A specific display, by its name (for example "LG UltraFine").
    case named(String)

    public init?(rawValue: String) {
        switch rawValue {
        case "notched": self = .notched
        case "main": self = .main
        case "mouse": self = .followMouse
        case let raw where raw.hasPrefix("name:"): self = .named(String(raw.dropFirst("name:".count)))
        default: return nil
        }
    }

    public var rawValue: String {
        switch self {
        case .notched: "notched"
        case .main: "main"
        case .followMouse: "mouse"
        case .named(let name): "name:\(name)"
        }
    }
}

/// Nocci's settings, saved to UserDefaults as they change.
@MainActor
@Observable
public final class NocciSettings {
    public static let widthRange: ClosedRange<Double> = 360...900
    public static let defaultWidth: Double = 560

    @ObservationIgnored private let defaults: UserDefaults

    public var alertDuration: AlertDuration {
        didSet { defaults.set(alertDuration.rawValue, forKey: SettingsKey.alertDuration) }
    }
    public var panelWidth: Double {
        didSet { defaults.set(panelWidth, forKey: SettingsKey.panelWidth) }
    }
    public var indicatorStyle: IndicatorStyle {
        didSet { defaults.set(indicatorStyle.rawValue, forKey: SettingsKey.indicatorStyle) }
    }
    public var indicatorSide: IndicatorSide {
        didSet { defaults.set(indicatorSide.rawValue, forKey: SettingsKey.indicatorSide) }
    }
    public var screenChoice: ScreenChoice {
        didSet { defaults.set(screenChoice.rawValue, forKey: SettingsKey.screenChoice) }
    }
    /// Seconds the mouse rests on the notch before the list opens.
    public var hoverOpenDelay: Double {
        didSet { defaults.set(hoverOpenDelay, forKey: SettingsKey.hoverOpenDelay) }
    }
    /// Seconds after the mouse leaves before the list closes.
    public var hoverCloseDelay: Double {
        didSet { defaults.set(hoverCloseDelay, forKey: SettingsKey.hoverCloseDelay) }
    }

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        alertDuration = defaults.string(forKey: SettingsKey.alertDuration).flatMap(AlertDuration.init(rawValue:)) ?? .tenSeconds
        let width = defaults.object(forKey: SettingsKey.panelWidth) as? Double ?? Self.defaultWidth
        panelWidth = min(max(width, Self.widthRange.lowerBound), Self.widthRange.upperBound)
        indicatorStyle = defaults.string(forKey: SettingsKey.indicatorStyle).flatMap(IndicatorStyle.init(rawValue:)) ?? .light
        indicatorSide = defaults.string(forKey: SettingsKey.indicatorSide).flatMap(IndicatorSide.init(rawValue:)) ?? .right
        screenChoice = defaults.string(forKey: SettingsKey.screenChoice).flatMap(ScreenChoice.init(rawValue:)) ?? .notched
        hoverOpenDelay = defaults.object(forKey: SettingsKey.hoverOpenDelay) as? Double ?? 0.2
        hoverCloseDelay = defaults.object(forKey: SettingsKey.hoverCloseDelay) as? Double ?? 0.4
    }

    /// Puts every setting back to its default.
    public func reset() {
        alertDuration = .tenSeconds
        panelWidth = Self.defaultWidth
        indicatorStyle = .light
        indicatorSide = .right
        screenChoice = .notched
        hoverOpenDelay = 0.2
        hoverCloseDelay = 0.4
    }
}
