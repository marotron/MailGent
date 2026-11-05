import AppKit
import Foundation

let out = URL(fileURLWithPath: CommandLine.arguments.count > 1
    ? CommandLine.arguments[1]
    : FileManager.default.currentDirectoryPath)
try FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)

let names = [
    "doc.on.clipboard",
    "arrow.right.doc.on.clipboard",
    "doc.on.doc",
    "plus.rectangle.on.rectangle",
    "rectangle.portrait.and.arrow.right",
    "arrow.right.square",
    "doc.badge.plus",
    "square.on.square",
    "xmark",
]
let sizes: [CGFloat] = [11, 22, 44]

for name in names {
    guard let base = NSImage(systemSymbolName: name, accessibilityDescription: nil) else {
        fputs("MISSING \(name)\n", stderr)
        continue
    }
    for size in sizes {
        let config = NSImage.SymbolConfiguration(pointSize: size * 0.72, weight: .bold)
        guard let configured = base.withSymbolConfiguration(config) else { continue }
        configured.isTemplate = true

        let padded = Int(size)
        guard let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: padded,
            pixelsHigh: padded,
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        ) else { continue }
        rep.size = NSSize(width: size, height: size)

        NSGraphicsContext.saveGraphicsState()
        guard let ctx = NSGraphicsContext(bitmapImageRep: rep) else {
            NSGraphicsContext.restoreGraphicsState()
            continue
        }
        NSGraphicsContext.current = ctx
        ctx.cgContext.clear(CGRect(x: 0, y: 0, width: size, height: size))

        let tint = NSColor(calibratedWhite: 0.45, alpha: 1)
        let colored = NSImage(size: NSSize(width: size, height: size), flipped: false) { rect in
            tint.set()
            configured.draw(in: rect, from: .zero, operation: .sourceOver, fraction: 1.0)
            return true
        }
        colored.draw(in: NSRect(x: 0, y: 0, width: size, height: size))
        NSGraphicsContext.restoreGraphicsState()

        guard let png = rep.representation(using: .png, properties: [:]) else { continue }
        let safe = name.replacingOccurrences(of: ".", with: "-")
        try png.write(to: out.appendingPathComponent("\(safe)-\(Int(size)).png"))
    }
    print("wrote \(name)")
}
