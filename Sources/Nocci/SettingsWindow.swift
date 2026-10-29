import AppKit
import NocciCore
import Observation
import SwiftUI

/// Which preview the settings window is showing in the notch. Reports every change.
@MainActor
@Observable
private final class PreviewModel {
    var selection: PanelController.Preview = .alert {
        didSet { onChange?(selection) }
    }
    @ObservationIgnored var onChange: ((PanelController.Preview) -> Void)?
}

/// A plugin as listed in Settings.
struct PluginInfo {
    let id: String
    let name: String
    let systemImage: String
}

/// Owns the settings window. While it is open the notch shows a fixed preview, so changes can be seen live.
@MainActor
final class SettingsWindowController: NSObject, NSWindowDelegate {
    private static let width: CGFloat = 460
    private static let height: CGFloat = 700

    private let settings: NocciSettings
    private let plugins: [PluginInfo]
    private let store: NotificationStore
    private let onPreviewChange: (PanelController.Preview?) -> Void
    private let model = PreviewModel()
    private var window: NSWindow?

    init(settings: NocciSettings, plugins: [PluginInfo], store: NotificationStore, onPreviewChange: @escaping (PanelController.Preview?) -> Void) {
        self.settings = settings
        self.plugins = plugins
        self.store = store
        self.onPreviewChange = onPreviewChange
        super.init()
        model.onChange = { [weak self] preview in
            guard self?.window?.isVisible == true else { return }
            self?.onPreviewChange(preview)
        }
    }

    /// Shows the window (creating it on first call), brings it to front, and starts the live preview.
    func show() {
        if window == nil { window = makeWindow() }
        guard let window else { return }
        NSApp.activate()
        window.makeKeyAndOrderFront(nil)
        onPreviewChange(model.selection)
    }

    func windowWillClose(_ notification: Notification) {
        onPreviewChange(nil)
    }

    private func makeWindow() -> NSWindow {
        let visibleHeight = NSScreen.main?.visibleFrame.height ?? Self.height
        let height = min(Self.height, visibleHeight - 40)
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: Self.width, height: height),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Nocci Settings"
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.contentView = NSHostingView(rootView: SettingsView(settings: settings, model: model, plugins: plugins, store: store))
        window.center()
        return window
    }
}

/// The settings form. Every control is bound straight to `NocciSettings`, which saves as it changes.
private struct SettingsView: View {
    @Bindable var settings: NocciSettings
    @Bindable var model: PreviewModel
    let plugins: [PluginInfo]
    let store: NotificationStore

    var body: some View {
        Form {
            Section {
                Picker("Preview", selection: $model.selection) {
                    ForEach(PanelController.Preview.allCases, id: \.self) { preview in
                        Text(previewLabel(preview)).tag(preview)
                    }
                }
                .pickerStyle(.segmented)
            } footer: {
                Text("While this window is open, the notch shows a preview.")
            }

            Section("Size") {
                LabeledContent("Width") {
                    HStack {
                        Slider(value: $settings.panelWidth, in: NocciSettings.widthRange, step: 10)
                        Text("\(Int(settings.panelWidth)) pt")
                            .monospacedDigit()
                            .frame(width: 60, alignment: .trailing)
                    }
                }
                LabeledContent("Text size") {
                    HStack {
                        Slider(value: $settings.fontScale, in: NocciSettings.fontScaleRange, step: 0.05)
                        Text(settings.fontScale.formatted(.percent.precision(.fractionLength(0))))
                            .monospacedDigit()
                            .frame(width: 60, alignment: .trailing)
                    }
                }
            }

            Section {
                // A List (not Form rows) so rows can be dragged to reorder.
                List {
                    ForEach(settings.pluginOrder, id: \.self) { id in
                        if let plugin = plugins.first(where: { $0.id == id }) {
                            Toggle(isOn: Binding(
                                get: { settings.enabledPlugins.contains(id) },
                                set: { settings.setPlugin(id, enabled: $0) }
                            )) {
                                Label(plugin.name, systemImage: plugin.systemImage)
                            }
                        }
                    }
                    .onMove { settings.pluginOrder.move(fromOffsets: $0, toOffset: $1) }
                }
                .frame(height: CGFloat(settings.pluginOrder.count) * 30 + 8)
                .scrollDisabled(true)
            } header: {
                Text("Plugins")
            } footer: {
                Text("Drag to reorder. When the island opens, plugins appear top to bottom in this order. Media asks for Automation (Music, Spotify) or Accessibility (other apps) permission the first time you use its controls.")
            }

            Section {
                let apps = store.knownApps
                if apps.isEmpty {
                    Text("No notifications yet.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(apps, id: \.bundleID) { app in
                        Toggle(isOn: Binding(
                            get: { !settings.hiddenApps.contains(app.bundleID) },
                            set: { shown in
                                if shown { settings.hiddenApps.remove(app.bundleID) } else { settings.hiddenApps.insert(app.bundleID) }
                            }
                        )) {
                            Label {
                                Text(app.name)
                            } icon: {
                                if let icon = AppInfo.icon(for: app.bundleID) {
                                    Image(nsImage: icon)
                                        .resizable()
                                        .frame(width: 16, height: 16)
                                } else {
                                    Image(systemName: "app")
                                        .frame(width: 16, height: 16)
                                }
                            }
                        }
                    }
                }
            } header: {
                Text("Apps")
            } footer: {
                Text("Only apps that have sent a notification are listed. Hidden apps don't alert or appear in the list.")
            }

            Section {
                Picker("Style", selection: $settings.indicatorStyle) {
                    Text("Green light").tag(IndicatorStyle.light)
                    Text("Number").tag(IndicatorStyle.count)
                    Text("Off").tag(IndicatorStyle.off)
                }
                Picker("Side", selection: $settings.indicatorSide) {
                    Text("Left of notch").tag(IndicatorSide.left)
                    Text("Right of notch").tag(IndicatorSide.right)
                }
                .pickerStyle(.segmented)
                .disabled(settings.indicatorStyle == .off)
            } header: {
                Text("Unread indicator")
            } footer: {
                Text("Hidden on screens without a notch.")
            }

            Section("Alerts") {
                Picker("Show for", selection: $settings.alertDuration) {
                    Text("5 seconds").tag(AlertDuration.fiveSeconds)
                    Text("10 seconds").tag(AlertDuration.tenSeconds)
                    Text("30 seconds").tag(AlertDuration.thirtySeconds)
                    Text("Until dismissed").tag(AlertDuration.untilDismissed)
                }
            }

            Section("Hover") {
                delaySlider("Open after", value: $settings.hoverOpenDelay, range: 0...1)
                delaySlider("Close after", value: $settings.hoverCloseDelay, range: 0...1.5)
            }

            Section {
                Picker("Show on", selection: $settings.screenChoice) {
                    ForEach(screenOptions, id: \.choice) { option in
                        Text(option.label).tag(option.choice)
                    }
                }
            } header: {
                Text("Display")
            } footer: {
                Text("Screens without a notch use the top center.")
            }

            Section {
                Button("Reset to Defaults") { settings.reset() }
            }
        }
        .formStyle(.grouped)
    }

    private func previewLabel(_ preview: PanelController.Preview) -> String {
        switch preview {
        case .alert: "Alert"
        case .list: "List"
        case .light: "Light"
        }
    }

    private func delaySlider(_ title: String, value: Binding<Double>, range: ClosedRange<Double>) -> some View {
        LabeledContent(title) {
            HStack {
                Slider(value: value, in: range, step: 0.05)
                Text(value.wrappedValue.formatted(.number.precision(.fractionLength(2))) + " s")
                    .monospacedDigit()
                    .frame(width: 60, alignment: .trailing)
            }
        }
    }

    /// The fixed choices, then one per connected screen. A saved screen that's unplugged stays in the list so
    /// the picker still has something to select.
    private var screenOptions: [(choice: ScreenChoice, label: String)] {
        var options: [(choice: ScreenChoice, label: String)] = [
            (.notched, "MacBook screen (notch)"),
            (.main, "Main display"),
            (.followMouse, "Follow the mouse"),
        ]
        let names = NSScreen.screens.map(\.localizedName)
        for name in names {
            options.append((.named(name), name))
        }
        if case .named(let saved) = settings.screenChoice, !names.contains(saved) {
            options.append((.named(saved), "\(saved) (not connected)"))
        }
        return options
    }
}
