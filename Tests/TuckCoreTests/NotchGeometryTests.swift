import CoreGraphics
import Testing
@testable import TuckCore

struct NotchGeometryTests {
    @Test func notchedScreenWrapsTheNotch() {
        // 1470 x 956 built-in screen, 185 pt notch, 32 pt tall.
        let screen = CGRect(x: 0, y: 0, width: 1470, height: 956)
        let geometry = NotchGeometry(screenFrame: screen, safeAreaTop: 32, auxiliaryLeftWidth: 642.5, auxiliaryRightWidth: 642.5)

        #expect(geometry.hasNotch)
        #expect(geometry.notchSize == CGSize(width: 185, height: 32))
        #expect(geometry.centerX == 735)

        let frame = geometry.panelFrame(contentSize: CGSize(width: 305, height: 28))
        #expect(frame.width == 305)
        #expect(frame.height == 60)
        #expect(frame.maxY == screen.maxY)
        #expect(abs(frame.midX - 735) <= 0.5)
    }

    @Test func panelIsNeverNarrowerThanTheNotch() {
        let screen = CGRect(x: 0, y: 0, width: 1470, height: 956)
        let geometry = NotchGeometry(screenFrame: screen, safeAreaTop: 32, auxiliaryLeftWidth: 642.5, auxiliaryRightWidth: 642.5)
        #expect(geometry.panelFrame(contentSize: CGSize(width: 50, height: 28)).width == 185)
    }

    @Test func screenWithoutNotchCentersOnTheScreen() {
        // A secondary display placed to the left of and above the origin.
        let screen = CGRect(x: -3440, y: 956, width: 3440, height: 1440)
        let geometry = NotchGeometry(screenFrame: screen, safeAreaTop: 0, auxiliaryLeftWidth: nil, auxiliaryRightWidth: nil)

        #expect(!geometry.hasNotch)
        let frame = geometry.panelFrame(contentSize: CGSize(width: 220, height: 28))
        #expect(frame == CGRect(x: -1830, y: 2368, width: 220, height: 28))
    }
}

extension NotchGeometryTests {
    @Test func hotZoneIsTheNotchOrAFallbackStrip() {
        let notched = NotchGeometry(screenFrame: CGRect(x: 0, y: 0, width: 1470, height: 956), safeAreaTop: 32, auxiliaryLeftWidth: 642.5, auxiliaryRightWidth: 642.5)
        #expect(notched.hotZone(fallbackSize: CGSize(width: 200, height: 24)) == CGRect(x: 642.5, y: 924, width: 185, height: 32))

        let plain = NotchGeometry(screenFrame: CGRect(x: 0, y: 0, width: 1000, height: 800), safeAreaTop: 0, auxiliaryLeftWidth: nil, auxiliaryRightWidth: nil)
        #expect(plain.hotZone(fallbackSize: CGSize(width: 200, height: 24)) == CGRect(x: 400, y: 776, width: 200, height: 24))
    }
}
