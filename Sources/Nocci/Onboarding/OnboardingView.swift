import AppKit
import ApplicationServices
import NocciCore
import SwiftUI

/// The paged walkthrough: one step at a time, with Back and Continue.
struct OnboardingView: View {
    let model: OnboardingModel
    let settings: NocciSettings

    var body: some View {
        VStack(spacing: 0) {
            stepContent
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                .padding(.horizontal, 40)
                .padding(.top, 32)
            Divider()
            footer
        }
        .frame(width: 520, height: 560)
    }

    @ViewBuilder
    private var stepContent: some View {
        switch model.step {
        case .welcome: WelcomeStep()
        case .fullDiskAccess: FullDiskAccessStep(model: model)
        case .banners: BannersStep()
        case .media: MediaStep(settings: settings)
        case .login: LoginStep()
        case .done: DoneStep()
        }
    }

    private var footer: some View {
        HStack {
            Button("Back") { move(by: -1) }
                .opacity(model.step == .welcome ? 0 : 1)
                .disabled(model.step == .welcome)
            Spacer()
            HStack(spacing: 8) {
                ForEach(OnboardingStep.allCases, id: \.self) { step in
                    Circle()
                        .fill(step == model.step ? Color.accentColor : Color.secondary.opacity(0.3))
                        .frame(width: 7, height: 7)
                }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Step \(model.step.rawValue + 1) of \(OnboardingStep.allCases.count)")
            Spacer()
            if model.step == .done {
                Button("Finish") { model.onFinish() }
                    .keyboardShortcut(.defaultAction)
            } else {
                Button(continueLabel) { move(by: 1) }
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 16)
    }

    private var continueLabel: String {
        model.step == .fullDiskAccess && model.access != .granted ? "Skip for now" : "Continue"
    }

    private func move(by offset: Int) {
        guard let next = OnboardingStep(rawValue: model.step.rawValue + offset) else { return }
        model.step = next
    }
}

// MARK: - Shared pieces

/// Opens a System Settings page.
@MainActor
private func openSettings(_ url: String) {
    if let url = URL(string: url) { NSWorkspace.shared.open(url) }
}

/// Icon, title, and a short intro, shared by every step after the welcome.
private struct StepHeader: View {
    let systemImage: String
    let title: String
    let tag: String?

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: systemImage)
                .font(.system(size: 40, weight: .regular))
                .foregroundStyle(Color.accentColor)
                .frame(height: 48)
            Text(title)
                .font(.title.weight(.semibold))
            if let tag {
                Text(tag)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 2)
                    .background(.quaternary, in: Capsule())
            }
        }
        .padding(.bottom, 16)
    }
}

/// A small status line: a symbol and a label.
private struct StatusRow: View {
    let isOn: Bool
    let onText: String
    let offText: String

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: isOn ? "checkmark.circle.fill" : "circle.dotted")
                .foregroundStyle(isOn ? Color.green : Color.secondary)
            Text(isOn ? onText : offText)
                .foregroundStyle(isOn ? Color.primary : Color.secondary)
        }
        .font(.body.weight(.medium))
        .padding(.vertical, 8)
        .padding(.horizontal, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.quaternary.opacity(0.6), in: RoundedRectangle(cornerRadius: 8))
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Steps

private struct WelcomeStep: View {
    var body: some View {
        VStack(spacing: 14) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 96, height: 96)
            Text("Welcome to Nocci")
                .font(.largeTitle.weight(.semibold))
            Text("Nocci shows your Mac notifications in the notch, like the Dynamic Island on iPhone.")
                .multilineTextAlignment(.center)
            VStack(alignment: .leading, spacing: 6) {
                Label("Your notifications stay on this Mac.", systemImage: "lock.fill")
                Label("Nothing is sent anywhere.", systemImage: "wifi.slash")
                Label("Message text is never saved.", systemImage: "eye.slash.fill")
            }
            .padding(.top, 6)
            Text("This takes about a minute.")
                .foregroundStyle(.secondary)
                .padding(.top, 6)
        }
        .font(.body)
        .fixedSize(horizontal: false, vertical: true)
    }
}

private struct FullDiskAccessStep: View {
    let model: OnboardingModel

    var body: some View {
        VStack(spacing: 12) {
            StepHeader(systemImage: "externaldrive.badge.checkmark", title: "Allow Full Disk Access", tag: "Required")
            Text("macOS keeps notifications in a protected place. To show them, Nocci needs Full Disk Access.")
                .multilineTextAlignment(.center)
            VStack(alignment: .leading, spacing: 4) {
                Text("1. Click Open Full Disk Access Settings.")
                Text("2. Click the + button and choose Nocci.")
                Text("3. Turn Nocci on.")
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, 4)
            HStack {
                Button("Open Full Disk Access Settings") {
                    openSettings("x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension?Privacy_AllFiles")
                }
                Button("Show Nocci in Finder") {
                    NSWorkspace.shared.activateFileViewerSelecting([Bundle.main.bundleURL])
                }
            }
            .padding(.top, 4)
            StatusRow(isOn: model.access == .granted, onText: "Access granted", offText: "Waiting for access…")
                .padding(.top, 8)
            if model.access == .blocked(databaseVisible: true) {
                VStack(spacing: 6) {
                    Text("Already turned it on? Relaunch Nocci so macOS applies it.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                    Button("Relaunch Nocci") { relaunch() }
                }
            }
        }
        .fixedSize(horizontal: false, vertical: true)
        .task {
            while !Task.isCancelled {
                model.access = await Task.detached { FullDiskAccessCheck.status() }.value
                try? await Task.sleep(for: .seconds(1))
            }
        }
    }

    private func relaunch() {
        Task {
            let configuration = NSWorkspace.OpenConfiguration()
            configuration.createsNewApplicationInstance = true
            _ = try? await NSWorkspace.shared.openApplication(at: Bundle.main.bundleURL, configuration: configuration)
            NSApp.terminate(nil)
        }
    }
}

private struct BannersStep: View {
    var body: some View {
        VStack(spacing: 12) {
            StepHeader(systemImage: "bell.slash", title: "Turn off Mac banners", tag: "Recommended")
            Text("Nocci replaces the banners that slide in at the top right. Turn those off so you don't see each notification twice.")
                .multilineTextAlignment(.center)
            VStack(alignment: .leading, spacing: 4) {
                Text("1. Click Open Notification Settings.")
                Text("2. Pick an app.")
                Text("3. Turn off Desktop.")
                Text("4. Leave Notification Center on.")
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, 4)
            Text("Notification Center has to stay on, or Nocci has nothing to show.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button("Open Notification Settings") {
                openSettings("x-apple.systempreferences:com.apple.Notifications-Settings.extension")
            }
            .padding(.top, 4)
        }
        .fixedSize(horizontal: false, vertical: true)
    }
}

private struct MediaStep: View {
    let settings: NocciSettings
    @State private var accessibilityOn = AXIsProcessTrusted()

    var body: some View {
        VStack(spacing: 12) {
            StepHeader(systemImage: "play.circle", title: "Media controls", tag: "Optional")
            Text("Nocci can show what's playing in Spotify, Apple Music, or YouTube, with play, pause, and skip.")
                .multilineTextAlignment(.center)
            Toggle("Show what's playing", isOn: Binding(
                get: { settings.enabledPlugins.contains("media") },
                set: { settings.setPlugin("media", enabled: $0) }
            ))
            .toggleStyle(.switch)
            .padding(.top, 4)
            Text("Spotify and Music ask for permission the first time you use the controls. Other apps, and the Escape key, need Accessibility.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button("Open Accessibility Settings") {
                openSettings("x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension?Privacy_Accessibility")
            }
            .padding(.top, 4)
            StatusRow(isOn: accessibilityOn, onText: "Accessibility on", offText: "Off (optional)")
        }
        .fixedSize(horizontal: false, vertical: true)
        .task {
            while !Task.isCancelled {
                accessibilityOn = AXIsProcessTrusted()
                try? await Task.sleep(for: .seconds(1))
            }
        }
    }
}

private struct LoginStep: View {
    @State private var opensAtLogin = LoginItem.isEnabled
    @State private var needsApproval = LoginItem.needsApproval
    @State private var errorText: String?

    var body: some View {
        VStack(spacing: 12) {
            StepHeader(systemImage: "power", title: "Open at login", tag: "Optional")
            Text("Start Nocci when you log in, so your notifications are always in the notch.")
                .multilineTextAlignment(.center)
            Toggle("Open Nocci at login", isOn: Binding(
                get: { opensAtLogin },
                set: { setEnabled($0) }
            ))
            .toggleStyle(.switch)
            .padding(.top, 4)
            if needsApproval {
                VStack(spacing: 6) {
                    Text("macOS needs your OK before Nocci can open at login.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                    Button("Open Login Items Settings") { LoginItem.openSettings() }
                }
            }
            if let errorText {
                Text(errorText)
                    .font(.callout)
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.center)
            }
        }
        .fixedSize(horizontal: false, vertical: true)
        .onAppear(perform: refresh)
    }

    private func setEnabled(_ enabled: Bool) {
        do {
            try LoginItem.setEnabled(enabled)
            errorText = nil
        } catch {
            errorText = "Couldn't change this: \(error.localizedDescription)"
        }
        refresh()
    }

    private func refresh() {
        opensAtLogin = LoginItem.isEnabled
        needsApproval = LoginItem.needsApproval
    }
}

private struct DoneStep: View {
    var body: some View {
        VStack(spacing: 14) {
            StepHeader(systemImage: "checkmark.circle.fill", title: "You're all set", tag: nil)
            Text("Hover over the notch to see your notifications.")
                .multilineTextAlignment(.center)
            Text("Right-click the notch for settings.")
                .multilineTextAlignment(.center)
        }
        .fixedSize(horizontal: false, vertical: true)
    }
}
