import AppKit
import NocciCore

/// Watches the mouse anywhere on screen and runs open or close after a short delay, so brushing past
/// the notch doesn't open the list and briefly leaving it doesn't close it.
///
/// Mouse-moved monitors need no permission (only key monitors require Accessibility).
@MainActor
final class HoverTracker {
    enum Action {
        case open, close
    }

    /// The action the mouse position calls for, or `nil` to do nothing.
    private let decide: (NSPoint) -> Action?
    private let perform: (Action) -> Void
    private var monitors: [Any] = []
    private var pending: Action?
    private var task: Task<Void, Never>?

    init(decide: @escaping (NSPoint) -> Action?, perform: @escaping (Action) -> Void) {
        self.decide = decide
        self.perform = perform
        // Global covers the mouse over other apps; local covers it over Nocci's own panel.
        let global = NSEvent.addGlobalMonitorForEvents(matching: [.mouseMoved, .leftMouseDragged]) { [weak self] _ in
            self?.mouseMoved()
        }
        let local = NSEvent.addLocalMonitorForEvents(matching: [.mouseMoved, .leftMouseDragged]) { [weak self] event in
            self?.mouseMoved()
            return event
        }
        monitors = [global, local].compactMap { $0 }
    }

    func mouseMoved() {
        let action = decide(NSEvent.mouseLocation)
        guard action != pending else { return }
        task?.cancel()
        pending = action
        guard let action else { return }

        let delay = switch action {
        case .open: UserDefaults.standard.object(forKey: SettingsKey.hoverOpenDelay) as? Double ?? 0.2
        case .close: UserDefaults.standard.object(forKey: SettingsKey.hoverCloseDelay) as? Double ?? 0.4
        }
        task = Task { [weak self] in
            try? await Task.sleep(for: .seconds(delay))
            guard !Task.isCancelled, let self else { return }
            pending = nil
            perform(action)
        }
    }
}
