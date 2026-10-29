import SwiftUI

/// The Dynamic Island–style shape that grows out of the notch: flush with the top edge, small concave "ears"
/// at the top corners so it blends into the bezel, and rounded bottom corners.
///
/// The ears sit outside the body, so the body is `width - 2 * ear` wide.
struct IslandShape: Shape {
    var ear: CGFloat
    var bottomRadius: CGFloat

    var animatableData: AnimatablePair<CGFloat, CGFloat> {
        get { AnimatablePair(ear, bottomRadius) }
        set { (ear, bottomRadius) = (newValue.first, newValue.second) }
    }

    func path(in rect: CGRect) -> Path {
        let w = rect.width, h = rect.height
        let e = min(ear, w / 2, h)
        let r = max(0, min(bottomRadius, (w - 2 * e) / 2, h - e))

        var path = Path()
        path.move(to: CGPoint(x: 0, y: 0))
        path.addQuadCurve(to: CGPoint(x: e, y: e), control: CGPoint(x: e, y: 0))
        path.addLine(to: CGPoint(x: e, y: h - r))
        path.addQuadCurve(to: CGPoint(x: e + r, y: h), control: CGPoint(x: e, y: h))
        path.addLine(to: CGPoint(x: w - e - r, y: h))
        path.addQuadCurve(to: CGPoint(x: w - e, y: h - r), control: CGPoint(x: w - e, y: h))
        path.addLine(to: CGPoint(x: w - e, y: e))
        path.addQuadCurve(to: CGPoint(x: w, y: 0), control: CGPoint(x: w - e, y: 0))
        path.closeSubpath()
        return path
    }
}
