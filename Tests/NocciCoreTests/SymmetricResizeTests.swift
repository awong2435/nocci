import CoreGraphics
import Testing
@testable import NocciCore

struct SymmetricResizeTests {
    let range: ClosedRange<Double> = 360...900

    @Test func draggingTheRightEdgeOutWidensByTwiceTheDistance() {
        #expect(SymmetricResize.width(edge: 1, startWidth: 560, startX: 1000, currentX: 1010, range: range) == 580)
    }

    @Test func draggingTheLeftEdgeOutWidensByTwiceTheDistance() {
        #expect(SymmetricResize.width(edge: -1, startWidth: 560, startX: 1000, currentX: 990, range: range) == 580)
    }

    @Test func draggingInwardNarrows() {
        #expect(SymmetricResize.width(edge: 1, startWidth: 560, startX: 1000, currentX: 950, range: range) == 460)
    }

    @Test func widthIsClampedAndRounded() {
        #expect(SymmetricResize.width(edge: 1, startWidth: 560, startX: 0, currentX: 1000, range: range) == 900)
        #expect(SymmetricResize.width(edge: 1, startWidth: 560, startX: 0, currentX: -1000, range: range) == 360)
        #expect(SymmetricResize.width(edge: 1, startWidth: 560, startX: 0, currentX: 0.3, range: range) == 561)
    }
}
