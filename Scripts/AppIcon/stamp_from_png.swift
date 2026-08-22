import AppKit
import Foundation

/// Stamp a 1024 master PNG into MailGent AppIcon.appiconset (Apple 824/1024 keyline).
///
///   swift Scripts/AppIcon/stamp_from_png.swift [master.png] [dest.iconset]

enum Spec {
    static let keylineRatio = 824.0 / 1024.0
    static let continuousCornerFraction = 0.2237
    static let macSizes: [(name: String, pixels: Int)] = [
        ("icon_16x16.png", 16),
        ("icon_16x16_2x.png", 32),
        ("icon_32x32.png", 32),
        ("icon_32x32_2x.png", 64),
        ("icon_128x128.png", 128),
        ("icon_128x128_2x.png", 256),
        ("icon_256x256.png", 256),
        ("icon_256x256_2x.png", 512),
        ("icon_512x512.png", 512),
        ("icon_512x512_2x.png", 1024),
    ]
}

func squircle(in rect: NSRect) -> NSBezierPath {
    let r = min(rect.width, rect.height) * Spec.continuousCornerFraction
    return NSBezierPath(roundedRect: rect, xRadius: r, yRadius: r)
}

func render(master: NSImage, px: Int) -> NSBitmapImageRep {
    let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px,
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
    )!
    NSGraphicsContext.saveGraphicsState()
    let ctx = NSGraphicsContext(bitmapImageRep: rep)!
    NSGraphicsContext.current = ctx
    ctx.imageInterpolation = .high
    ctx.shouldAntialias = true
    ctx.cgContext.clear(CGRect(x: 0, y: 0, width: px, height: px))

    let tileSidePx = max(1, Int((Double(px) * Spec.keylineRatio).rounded()))
    let originPx = (px - tileSidePx) / 2
    let tile = NSRect(
        x: CGFloat(originPx), y: CGFloat(originPx),
        width: CGFloat(tileSidePx), height: CGFloat(tileSidePx)
    )
    squircle(in: tile).addClip()
    master.draw(in: tile, from: .zero, operation: .sourceOver, fraction: 1)
    NSGraphicsContext.restoreGraphicsState()
    return rep
}

let scriptURL = URL(fileURLWithPath: CommandLine.arguments[0]).standardizedFileURL
let repoRoot = scriptURL.deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
let args = Array(CommandLine.arguments.dropFirst())
let masterPath = args.first
    ?? repoRoot.appendingPathComponent("Design/IconPack/glass-marketing.png").path
let dest = args.dropFirst().first
    ?? repoRoot.appendingPathComponent("MailGent/Assets.xcassets/AppIcon.appiconset").path

guard let master = NSImage(contentsOfFile: masterPath) else {
    fputs("unreadable master \(masterPath)\n", stderr)
    exit(1)
}

try FileManager.default.createDirectory(atPath: dest, withIntermediateDirectories: true)
print("Stamping \(masterPath)")
print("  → \(dest)")
print(String(format: "  keyline %.6f (824/1024)", Spec.keylineRatio))

for slot in Spec.macSizes {
    let data = render(master: master, px: slot.pixels).representation(using: .png, properties: [:])!
    try data.write(to: URL(fileURLWithPath: dest).appendingPathComponent(slot.name))
    print(String(format: "  wrote %@ (%d px)", slot.name as NSString, slot.pixels))
}
print("done")
