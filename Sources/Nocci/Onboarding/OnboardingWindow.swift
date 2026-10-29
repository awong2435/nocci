import AppKit
import NocciCore
import Observation
import SwiftUI

/// Whether Nocci can read the notification database. Structure-only check; never touches notification text.
enum FullDiskAccessCheck {
    enum Status: Equatable {
        case granted
        /// Can't read it yet. `databaseVisible` means the file is there but opening it failed,
        /// which usually means access was just granted and the app needs a relaunch.
        case blocked(databaseVisible: Bool)
    }

    static func status() -> Status {
        guard let url = DatabaseSource.locate() else { return .blocked(databaseVisible: false) }
        do {
            _ = try DatabaseSource(url: url).describeSchema()
            return .granted
        } catch {
            return .blocked(databaseVisible: true)
        }
    }
}

/// The steps of the first-run guide, in order.
enum OnboardingStep: Int, CaseIterable {
    case welcome, fullDiskAccess, banners, media, login, done
}

/// Where the guide is, and what the Full Disk Access step last found.
@MainActor
@Observable
final class OnboardingModel {
    var step: OnboardingStep = .welcome
    var access: FullDiskAccessCheck.Status = .blocked(databaseVisible: false)
    @ObservationIgnored var onFinish: () -> Void = {}
}

/// Owns the first-run setup guide window.
@MainActor
final class OnboardingWindowController: NSObject, NSWindowDelegate {
    private static let completedKey = "onboardingCompleted"

    private let settings: NocciSettings
    private let onFinish: () -> Void
    private let model = OnboardingModel()
    private var window: NSWindow?
    private var finished = false

    init(settings: NocciSettings, onFinish: @escaping () -> Void) {
        self.settings = settings
        self.onFinish = onFinish
        super.init()
        model.onFinish = { [weak self] in self?.window?.close() }
    }

    /// Whether Full Disk Access is missing (the notification database can't be opened). Cheap; safe to call at launch.
    static var needsFullDiskAccess: Bool {
        FullDiskAccessCheck.status() != .granted
    }

    /// Shows the guide (creating the window once), activates the app, brings it to front.
    func show() {
        if window == nil { window = makeWindow() }
        guard let window else { return }
        if !window.isVisible {
            model.step = .welcome
            finished = false
        }
        NSApp.activate()
        window.makeKeyAndOrderFront(nil)
    }

    /// Runs on Finish and on the close button alike.
    func windowWillClose(_ notification: Notification) {
        guard !finished else { return }
        finished = true
        UserDefaults.standard.set(true, forKey: Self.completedKey)
        onFinish()
    }

    private func makeWindow() -> NSWindow {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 520, height: 560),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "Welcome to Nocci"
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.contentView = NSHostingView(rootView: OnboardingView(model: model, settings: settings))
        window.center()
        return window
    }
}
