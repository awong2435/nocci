import ServiceManagement

/// Opening Nocci at login, through macOS's own login items (System Settings › General › Login Items).
/// macOS keeps the state, so nothing is saved in Nocci's settings.
enum LoginItem {
    static var isEnabled: Bool {
        SMAppService.mainApp.status == .enabled
    }

    /// macOS registered it but wants the user to approve it in System Settings first.
    static var needsApproval: Bool {
        SMAppService.mainApp.status == .requiresApproval
    }

    static func setEnabled(_ enabled: Bool) throws {
        if enabled {
            try SMAppService.mainApp.register()
        } else {
            try SMAppService.mainApp.unregister()
        }
    }

    static func openSettings() {
        SMAppService.openSystemSettingsLoginItems()
    }
}
