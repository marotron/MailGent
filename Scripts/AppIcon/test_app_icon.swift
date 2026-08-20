import AppKit
import Foundation

/// TDD seam: public AppIcon PNGs in the asset catalog.
/// Asserts Apple keyline tile size (824/1024), exact pixel slots, transparent outside tile.
///
/// Usage:
///   swift Scripts/AppIcon/test_app_icon.swift [path/to/AppIcon.appiconset]

enum Spec {
    static let keylineRatio = 824.0 / 1024.0
    static let keylineTolerance = 0.015
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

struct TileMetrics {
    var widthRatio: Double
    var heightRatio: Double
    var cornerAlpha: Double
    var pixelsWide: Int
    var pixelsHigh: Int
}

func loadRep(_ path: String) -> NSBitmapImageRep? {
    guard let img = NSImage(contentsOfFile: path),
          let tiff = img.tiffRepresentation,
          let rep = NSBitmapImageRep(data: tiff) else { return nil }
    return rep
}

func measureTile(_ path: String) -> TileMetrics? {
    guard let rep = loadRep(path) else { return nil }
    let w = rep.pixelsWide, h = rep.pixelsHigh
    func alpha(_ x: Int, _ y: Int) -> CGFloat {
        let c = rep.colorAt(x: x, y: y)!
        var r = CGFloat(0), g = CGFloat(0), b = CGFloat(0), a = CGFloat(0)
        c.getRed(&r, green: &g, blue: &b, alpha: &a)
        return a
    }

    var tMinX = w, tMinY = h, tMaxX = 0, tMaxY = 0
    for y in 0..<h {
        for x in 0..<w {
            if alpha(x, y) > 0.5 {
                tMinX = min(tMinX, x); tMinY = min(tMinY, y)
                tMaxX = max(tMaxX, x); tMaxY = max(tMaxY, y)
            }
        }
    }
    guard tMaxX > tMinX else { return nil }
    let tw = tMaxX - tMinX + 1
    let th = tMaxY - tMinY + 1
    return TileMetrics(
        widthRatio: Double(tw) / Double(w),
        heightRatio: Double(th) / Double(h),
        cornerAlpha: Double(alpha(0, 0)),
        pixelsWide: w,
        pixelsHigh: h
    )
}

let repoRoot = URL(fileURLWithPath: CommandLine.arguments[0])
    .standardizedFileURL
    .deletingLastPathComponent()
    .deletingLastPathComponent()
    .deletingLastPathComponent()

let iconsetArg = CommandLine.arguments.dropFirst().first
let iconsetPath = iconsetArg
    ?? repoRoot.appendingPathComponent("MailGent/Assets.xcassets/AppIcon.appiconset").path

var failures: [String] = []
var checks = 0

func expect(_ cond: Bool, _ message: String) {
    checks += 1
    if !cond { failures.append(message) }
}

print("AppIcon size test")
print("  iconset: \(iconsetPath)")
print(String(format: "  Apple keyline ratio: %.6f (±%.3f)", Spec.keylineRatio, Spec.keylineTolerance))
print("")

for slot in Spec.macSizes {
    let path = (iconsetPath as NSString).appendingPathComponent(slot.name)
    expect(FileManager.default.fileExists(atPath: path), "missing \(slot.name)")

    guard let m = measureTile(path) else {
        failures.append("unreadable \(slot.name)")
        checks += 1
        continue
    }

    expect(
        m.pixelsWide == slot.pixels && m.pixelsHigh == slot.pixels,
        "\(slot.name) pixels \(m.pixelsWide)x\(m.pixelsHigh), want \(slot.pixels)x\(slot.pixels)"
    )

    expect(
        m.cornerAlpha < 0.05,
        String(format: "%@ corner alpha %.3f, want ~0 (transparent outside tile)", slot.name, m.cornerAlpha)
    )

    let wOK = abs(m.widthRatio - Spec.keylineRatio) <= Spec.keylineTolerance
    let hOK = abs(m.heightRatio - Spec.keylineRatio) <= Spec.keylineTolerance
    expect(
        wOK && hOK,
        String(
            format: "%@ tile ratio W=%.4f H=%.4f, want %.4f ±%.3f (Apple 824/1024 keyline)",
            slot.name, m.widthRatio, m.heightRatio, Spec.keylineRatio, Spec.keylineTolerance
        )
    )

    let status = (wOK && hOK && m.cornerAlpha < 0.05) ? "OK" : "FAIL"
    print(String(
        format: "  %@  %dx%d  tile=%.4f  cornerA=%.2f  %@",
        slot.name as NSString, m.pixelsWide, m.pixelsHigh, m.widthRatio, m.cornerAlpha,
        status as NSString
    ))
}

print("")
if failures.isEmpty {
    print("PASS (\(checks) checks) — icons match Apple keyline sizing")
    exit(0)
} else {
    print("FAIL (\(failures.count)/\(checks) checks):")
    for f in failures { print("  • \(f)") }
    exit(1)
}
