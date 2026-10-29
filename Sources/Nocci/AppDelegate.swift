import AppKit
import Observation
import OSLog
import NocciCore

private let log = Logger(subsystem: "local.nocci", category: "app")

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let settings = NocciSettings()
    private lazy var model = PanelModel(store: AppDelegate.restoredStore(), alertDuration: settings.alertDuration)

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
    /// Every compiled-in plugin. Settings decides which are on and their order.
    private lazy var plugins: [any NocciPlugin] = [MediaPlugin(), NotificationsPlugin(store: model.store)]
    private var activePluginIDs: Set<String> = []
    private var panelController: PanelController?
    private var settingsWindow: SettingsWindowController?
    private var setupGuide: OnboardingWindowController?
    private var statusItem: NSStatusItem?
    private let statusLine = NSMenuItem(title: "Starting…", action: nil, keyEquivalent: "")
    private var listenTask: Task<Void, Never>?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Menu bar only, no Dock icon (LSUIElement covers the bundled app; this covers `swift run`).
        NSApp.setActivationPolicy(.accessory)
        panelController = PanelController(model: model, settings: settings, plugins: plugins) { [weak self] in
            self?.showSettings()
        }
        activatePluginsOnChange()
        setUpStatusItem()
        saveReadStateOnChange()
        applyAlertDurationOnChange()
        startListening()
        // First launch, or Full Disk Access still missing: walk through setup.
        if !UserDefaults.standard.bool(forKey: "onboardingCompleted") || OnboardingWindowController.needsFullDiskAccess {
            showSetupGuide()
        }
    }

    @objc private func showSetupGuide() {
        if setupGuide == nil {
            setupGuide = OnboardingWindowController(settings: settings) {}
        }
        setupGuide?.show()
    }

    @objc private func showSettings() {
        if settingsWindow == nil {
            let pluginInfo = plugins.map { PluginInfo(id: $0.id, name: $0.name, systemImage: $0.systemImage) }
            settingsWindow = SettingsWindowController(
                settings: settings,
                plugins: pluginInfo,
                store: model.store,
                onShowGuide: { [weak self] in self?.showSetupGuide() }
            ) { [weak self] preview in
                self?.panelController?.preview = preview
            }
        }
        settingsWindow?.show()
    }

    /// Starts turned-on plugins and stops turned-off ones, now and whenever Settings changes.
    /// Only calls `setActive` when a plugin's state actually changes.
    private func activatePluginsOnChange() {
        withObservationTracking {
            for plugin in plugins {
                let active = settings.enabledPlugins.contains(plugin.id)
                guard activePluginIDs.contains(plugin.id) != active else { continue }
                if active { activePluginIDs.insert(plugin.id) } else { activePluginIDs.remove(plugin.id) }
                plugin.setActive(active)
            }
        } onChange: { [weak self] in
            Task { @MainActor in self?.activatePluginsOnChange() }
        }
    }

    /// Keeps the model's alert duration and the store's hidden apps in step with Settings.
    private func applyAlertDurationOnChange() {
        withObservationTracking {
            model.alertDuration = settings.alertDuration
            model.store.hiddenApps = settings.hiddenApps
        } onChange: { [weak self] in
            Task { @MainActor in self?.applyAlertDurationOnChange() }
        }
    }

    /// Nocci's panel shouldn't activate the app. Logged to diagnose clicks that do.
    func applicationDidBecomeActive(_ notification: Notification) {
        log.notice("app became active")
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
        item.button?.image = NSImage(systemSymbolName: "rectangle.topthird.inset.filled", accessibilityDescription: "Nocci")

        let menu = NSMenu()
        statusLine.isEnabled = false
        menu.addItem(statusLine)
        menu.addItem(.separator())

        let settingsItem = NSMenuItem(title: "Settings…", action: #selector(showSettings), keyEquivalent: ",")
        settingsItem.target = self
        menu.addItem(settingsItem)
        let guideItem = NSMenuItem(title: "Setup Guide…", action: #selector(showSetupGuide), keyEquivalent: "")
        guideItem.target = self
        menu.addItem(guideItem)

        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit Nocci", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        item.menu = menu
        statusItem = item
    }
}
