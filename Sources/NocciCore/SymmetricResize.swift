import CoreGraphics

/// Width math for dragging a side edge of the island. Both edges move together, so the island stays centered:
/// dragging the right edge out by 10 pt (or the left edge out by 10 pt) widens it by 20.
public enum SymmetricResize {
    /// - Parameters:
    ///   - edge: -1 for the left edge, +1 for the right.
    ///   - startWidth: width when the drag began.
    ///   - startX, currentX: global mouse x when the drag began and now.
    /// - Returns: the new width, rounded to whole points and clamped to `range`.
    public static func width(edge: CGFloat, startWidth: Double, startX: CGFloat, currentX: CGFloat, range: ClosedRange<Double>) -> Double {
        let width = startWidth + 2 * Double(edge * (currentX - startX))
        return min(max(width, range.lowerBound), range.upperBound).rounded()
    }
}
