// Builds Resources/AppIcon.icns from the logo artwork.
// Usage: swift scripts/make-icon.swift Resources/Icon/source.jpg Resources/AppIcon.icns
//
// Finds the dark rounded square in the artwork, crops it, and places it on Apple's macOS icon grid
// (an 824 pt shape centered on a 1024 pt canvas, with transparent corners), then runs iconutil.
import AppKit

let arguments = CommandLine.arguments
guard arguments.count == 3,
      let source = NSImage(contentsOfFile: arguments[1])?.cgImage(forProposedRect: nil, context: nil, hints: nil)
else {
    FileHandle.standardError.write(Data("usage: make-icon.swift <artwork> <output.icns>\n".utf8))
    exit(1)
}

// Bounding box of the dark shape: pixels well below the light background.
let width = source.width, height = source.height
var pixels = [UInt8](repeating: 0, count: width * height * 4)
let rgb = CGColorSpace(name: CGColorSpace.sRGB)!
let reader = CGContext(data: &pixels, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
                       space: rgb, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
reader.draw(source, in: CGRect(x: 0, y: 0, width: width, height: height))
var minX = width, minY = height, maxX = 0, maxY = 0
for y in 0..<height {
    for x in 0..<width {
        let i = (y * width + x) * 4
        if Int(pixels[i]) + Int(pixels[i + 1]) + Int(pixels[i + 2]) < 3 * 110 {
            minX = min(minX, x); maxX = max(maxX, x); minY = min(minY, y); maxY = max(maxY, y)
        }
    }
}
// Trim a few pixels so the anti-aliased edge against the background doesn't show.
let inset = 4
// The context's buffer is bottom-up, so flip y for cropping, which uses a top-left origin.
let crop = CGRect(x: minX + inset, y: height - 1 - maxY + inset,
                  width: maxX - minX + 1 - 2 * inset, height: maxY - minY + 1 - 2 * inset)
let shape = source.cropping(to: crop)!

func render(size: Int) -> Data {
    let scale = CGFloat(size) / 1024
    let context = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0,
                            space: rgb, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    context.interpolationQuality = .high
    let body = CGRect(x: 100 * scale, y: 100 * scale, width: 824 * scale, height: 824 * scale)
    context.addPath(CGPath(roundedRect: body, cornerWidth: 200 * scale, cornerHeight: 200 * scale, transform: nil))
    context.clip()
    context.draw(shape, in: body)
    let rep = NSBitmapImageRep(cgImage: context.makeImage()!)
    return rep.representation(using: .png, properties: [:])!
}

let iconset = FileManager.default.temporaryDirectory.appending(path: "AppIcon-\(UUID().uuidString).iconset")
try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)
for points in [16, 32, 128, 256, 512] {
    try render(size: points).write(to: iconset.appending(path: "icon_\(points)x\(points).png"))
    try render(size: points * 2).write(to: iconset.appending(path: "icon_\(points)x\(points)@2x.png"))
}

let iconutil = Process()
iconutil.executableURL = URL(filePath: "/usr/bin/iconutil")
iconutil.arguments = ["-c", "icns", iconset.path, "-o", arguments[2]]
try iconutil.run()
iconutil.waitUntilExit()
try? FileManager.default.removeItem(at: iconset)
print("crop: \(crop), wrote \(arguments[2])")
exit(iconutil.terminationStatus)
