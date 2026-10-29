import AppKit
import CoreImage
import CoreImage.CIFilterBuiltins
import SwiftUI

/// Picks a waveform color from artwork.
enum ArtworkTint {
    /// Shown when there's no artwork.
    static let fallback = Color(white: 0.7)

    /// The artwork's average color, slightly brightened and desaturated like iOS. Fallback gray if it can't be read.
    static func color(for image: NSImage?) -> Color {
        guard let image,
              let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return fallback }
        let input = CIImage(cgImage: cgImage)
        let filter = CIFilter.areaAverage()
        filter.inputImage = input
        filter.extent = input.extent
        guard let output = filter.outputImage,
              let space = CGColorSpace(name: CGColorSpace.sRGB) else { return fallback }
        var pixel = [UInt8](repeating: 0, count: 4)
        CIContext().render(output, toBitmap: &pixel, rowBytes: 4,
                           bounds: CGRect(x: 0, y: 0, width: 1, height: 1), format: .RGBA8, colorSpace: space)
        let average = NSColor(srgbRed: CGFloat(pixel[0]) / 255, green: CGFloat(pixel[1]) / 255,
                              blue: CGFloat(pixel[2]) / 255, alpha: 1)
        var hue: CGFloat = 0, saturation: CGFloat = 0, brightness: CGFloat = 0
        average.getHue(&hue, saturation: &saturation, brightness: &brightness, alpha: nil)
        return Color(hue: Double(hue),
                     saturation: Double(saturation * 0.8),
                     brightness: Double(max(0.65, min(1, brightness * 1.15 + 0.1))))
    }
}
