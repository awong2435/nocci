import AppKit
import Observation
import OSLog
import TuckCore

private let log = Logger(subsystem: "local.tuck", category: "app")

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let model = PanelModel(
        store: AppDelegate.restoredStore(),
        alertDuration: UserDefaults.standard.string(forKey: SettingsKey.alertDuration)
            .flatMap(AlertDuration.init(rawValue:)) ?? .tenSeconds
    )

    /// Restores the last-opened time and dismissed IDs. On first launch, everything already in
    /// Notification Center counts as read, so the counter starts at zero.
    private static func restoredStore() -> NotificationStore {
        let defaults = UserDefaults.standard
        let lastOpened = defaults.object(forKey: SettingsKey.lastOpened) as? Date ?? {
            let now = Date()
            defaults.set(now, forKey: SettingsKey.lastOpened)
            return now
        }()
        let dismissed = Set(defaults.stringArray(forKey: SettingsKey.dismissedIDs) ?? [])
        return NotificationStore(lastOpened: lastOpened, dismissedIDs: dismissed)
    }
    private var panelController: PanelController?
    private var statusItem: NSStatusItem?
    private let statusLine = NSMenuItem(title: "Starting…", action: nil, keyEquivalent: "")
    private var listenTask: Task<Void, Never>?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Menu bar only, no Dock icon (LSUIElement covers the bundled app; this covers `swift run`).
        NSApp.setActivationPolicy(.accessory)
        panelController = PanelController(model: model)
        setUpStatusItem()
        saveReadStateOnChange()
        startListening()
    }

    /// Saves the last-opened time and dismissed IDs whenever they change. Never message text.
    private func saveReadStateOnChange() {
        let store = model.store
        withObservationTracking {
            _ = store.lastOpened
            _ = store.dismissedIDs
        } onChange: { [weak self] in
            Task { @MainActor in
                UserDefaults.standard.set(store.lastOpened, forKey: SettingsKey.lastOpened)
                UserDefaults.standard.set(Array(store.dismissedIDs), forKey: SettingsKey.dismissedIDs)
                self?.saveReadStateOnChange()
            }
        }
    }

    /// Loads existing notifications without alerting, then alerts on each new one.
    /// `--mock` uses fake notifications every 8 seconds instead of the real database.
    private func startListening() {
        let source: any NotificationSource
        if CommandLine.arguments.contains("--mock") {
            source = MockSource(interval: .seconds(8))
        } else if let url = DatabaseSource.locate() {
            source = DatabaseSource(url: url, pollInterval: .seconds(1), appName: AppInfo.name(for:))
        } else {
            statusLine.title = "Notification database not found"
            return
        }

        listenTask = Task { [model, statusLine] in
            do {
                model.store.ingest(try await source.recent(limit: 200))
                model.refresh()
                statusLine.title = "Watching notifications"
            } catch {
                // DatabaseError descriptions contain codes only, never notification text.
                log.error("Couldn't read notifications: \(String(describing: error), privacy: .public)")
                statusLine.title = "No access: grant Full Disk Access, then relaunch"
                return
            }
            for await item in source.newItems() {
                model.receive(item)
            }
        }
    }

    private func setUpStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.button?.image = NSImage(systemSymbolName: "rectangle.topthird.inset.filled", accessibilityDescription: "Tuck")

        let menu = NSMenu()
        statusLine.isEnabled = false
        menu.addItem(statusLine)
        menu.addItem(.separator())

        let durationItem = NSMenuItem(title: "Alert Duration", action: nil, keyEquivalent: "")
        let durationMenu = NSMenu()
        for duration in AlertDuration.allCases {
            let option = NSMenuItem(title: duration.title, action: #selector(chooseDuration(_:)), keyEquivalent: "")
            option.target = self
            option.representedObject = duration.rawValue
            option.state = duration == model.alertDuration ? .on : .off
            durationMenu.addItem(option)
        }
        durationItem.submenu = durationMenu
        menu.addItem(durationItem)

        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit Tuck", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        item.menu = menu
        statusItem = item
    }

    @objc private func chooseDuration(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String, let duration = AlertDuration(rawValue: raw) else { return }
        model.alertDuration = duration
        UserDefaults.standard.set(raw, forKey: SettingsKey.alertDuration)
        sender.menu?.items.forEach { $0.state = $0 === sender ? .on : .off }
    }
}

private extension AlertDuration {
    var title: String {
        switch self {
        case .fiveSeconds: "5 seconds"
        case .tenSeconds: "10 seconds"
        case .thirtySeconds: "30 seconds"
        case .untilDismissed: "Until dismissed"
        }
    }
}
