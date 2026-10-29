import Foundation

/// Carries settings over when the app ID changes, so a new ID doesn't reset them. UserDefaults are stored per
/// app ID; on the first launch under a new ID, copy everything from an older one.
enum SettingsMigration {
    /// Every app ID Nocci has shipped under, oldest first.
    static let previousIDs = ["local.nocci"]

    static func run() {
        let defaults = UserDefaults.standard
        guard let current = Bundle.main.bundleIdentifier, !previousIDs.contains(current),
              !defaults.bool(forKey: "migratedSettings") else { return }
        for old in previousIDs.reversed() {
            guard let values = defaults.persistentDomain(forName: old), !values.isEmpty else { continue }
            for (key, value) in values where defaults.object(forKey: key) == nil {
                defaults.set(value, forKey: key)
            }
            break
        }
        defaults.set(true, forKey: "migratedSettings")
    }
}
