import CoreGraphics

/// Notch measurements for one screen, and where the panel goes.
///
/// Pure value type so it can be tested without a real `NSScreen`.
/// Coordinates are AppKit screen coordinates (origin bottom-left).
public struct NotchGeometry: Equatable, Sendable {
    public let screenFrame: CGRect
    /// Notch size, or `.zero` on screens without one.
    public let notchSize: CGSize
    /// Horizontal center of the notch (or of the screen when there is none).
    public let centerX: CGFloat

    public var hasNotch: Bool { notchSize.width > 0 && notchSize.height > 0 }

    /// - Parameters:
    ///   - safeAreaTop: `NSScreen.safeAreaInsets.top`; 0 on screens without a notch.
    ///   - auxiliaryLeftWidth: width of `NSScreen.auxiliaryTopLeftArea`, if any.
    ///   - auxiliaryRightWidth: width of `NSScreen.auxiliaryTopRightArea`, if any.
    public init(
        screenFrame: CGRect,
        safeAreaTop: CGFloat,
        auxiliaryLeftWidth: CGFloat?,
        auxiliaryRightWidth: CGFloat?
    ) {
        self.screenFrame = screenFrame
        if safeAreaTop > 0, let left = auxiliaryLeftWidth, let right = auxiliaryRightWidth {
            let width = max(0, screenFrame.width - left - right)
            notchSize = CGSize(width: width, height: safeAreaTop)
            centerX = screenFrame.minX + left + width / 2
        } else {
            notchSize = .zero
            centerX = screenFrame.midX
        }
    }

    /// Area at the top edge that reveals the list on hover: the notch itself,
    /// or a `fallbackSize` strip at the top center on screens without one.
    public func hotZone(fallbackSize: CGSize) -> CGRect {
        let size = hasNotch ? notchSize : fallbackSize
        return CGRect(x: centerX - size.width / 2, y: screenFrame.maxY - size.height, width: size.width, height: size.height)
    }

    /// Panel frame for content shown below the notch, flush with the top edge and centered on the notch.
    /// On a notched screen the panel also covers the notch itself, so it is `notchSize.height` taller.
    public func panelFrame(contentSize: CGSize) -> CGRect {
        let width = max(contentSize.width, notchSize.width)
        let height = notchSize.height + contentSize.height
        return CGRect(
            x: (centerX - width / 2).rounded(),
            y: screenFrame.maxY - height,
            width: width.rounded(),
            height: height
        )
    }
}
