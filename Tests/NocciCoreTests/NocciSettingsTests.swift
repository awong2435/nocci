import Foundation
import Testing
@testable import NocciCore

@MainActor
struct NocciSettingsTests {
    let defaults: UserDefaults

    init() {
        let suite = "nocci-settings-test-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
    }

    @Test func startsWithDefaults() {
        let settings = NocciSettings(defaults: defaults)
        #expect(settings.alertDuration == .tenSeconds)
        #expect(settings.panelWidth == 560)
        #expect(settings.indicatorStyle == .light)
        #expect(settings.indicatorSide == .right)
        #expect(settings.screenChoice == .notched)
        #expect(settings.hoverOpenDelay == 0.2)
        #expect(settings.hoverCloseDelay == 0.4)
    }

    @Test func changesAreSavedAndReloaded() {
        let settings = NocciSettings(defaults: defaults)
        settings.panelWidth = 700
        settings.indicatorStyle = .count
        settings.indicatorSide = .left
        settings.hoverOpenDelay = 0.5
        settings.screenChoice = .named("LG UltraFine")

        let reloaded = NocciSettings(defaults: defaults)
        #expect(reloaded.panelWidth == 700)
        #expect(reloaded.indicatorStyle == .count)
        #expect(reloaded.indicatorSide == .left)
        #expect(reloaded.hoverOpenDelay == 0.5)
        #expect(reloaded.screenChoice == .named("LG UltraFine"))
    }

    @Test func screenChoiceRoundTripsThroughItsRawValue() {
        for choice in [ScreenChoice.notched, .main, .followMouse, .named("Studio Display")] {
            #expect(ScreenChoice(rawValue: choice.rawValue) == choice)
        }
        #expect(ScreenChoice(rawValue: "bogus") == nil)
    }

    @Test func savedWidthIsClampedToTheAllowedRange() {
        defaults.set(5_000.0, forKey: SettingsKey.panelWidth)
        #expect(NocciSettings(defaults: defaults).panelWidth == NocciSettings.widthRange.upperBound)
    }

    @Test func resetRestoresDefaults() {
        let settings = NocciSettings(defaults: defaults)
        settings.panelWidth = 800
        settings.indicatorStyle = .off
        settings.reset()
        #expect(settings.panelWidth == 560)
        #expect(settings.indicatorStyle == .light)
        #expect(NocciSettings(defaults: defaults).panelWidth == 560)
    }
}
