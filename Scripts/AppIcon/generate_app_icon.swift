import AppKit
import Foundation

/// Generate MailGent macOS AppIcon PNGs sized to Apple's 824/1024 keyline.
/// Same plate + cream language as ArchMail. Marks are MailGent (companion, not archive).
///
/// Usage:
///   swift Scripts/AppIcon/generate_app_icon.swift [dest] [--design NAME|N]
///
/// Designs 1…4 — flat Apple-simple marks:
///   1 companion  folded letter + presence pip          ← default
///   2 pair       letter beside a small agent disc
///   3 mono       geometric G
///   4 seal       round badge, flap + pip

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

enum Design: String, CaseIterable {
    case companion, pair, mono, seal

    var number: Int { Self.allCases.firstIndex(of: self)! + 1 }

    var title: String {
        switch self {
        case .companion: return "Companion"
        case .pair: return "Pair"
        case .mono: return "Mono"
        case .seal: return "Seal"
        }
    }

    var blurb: String {
        switch self {
        case .companion: return "Folded letter with a companion pip"
        case .pair: return "Mail beside a named agent"
        case .mono: return "Geometric Gent G"
        case .seal: return "Grant seal — flap plus pip"
        }
    }

    var principle: String {
        switch self {
        case .companion: return "ArchMail envelope language. Pip is the Gent. Two shapes, one idea."
        case .pair: return "Companion posture: mail stays, agent sits beside it."
        case .mono: return "Letterform as logo. No ornament."
        case .seal: return "Badge mark. Reads as grant / pairing."
        }
    }

    var label: String { "\(number) · \(title)" }

    static func parse(_ raw: String) -> Design? {
        let s = raw.lowercased()
        if let n = Int(s), (1...allCases.count).contains(n) {
            return allCases[n - 1]
        }
        return Design(rawValue: s)
    }
}

func squircle(in rect: NSRect) -> NSBezierPath {
    let r = min(rect.width, rect.height) * Spec.continuousCornerFraction
    return NSBezierPath(roundedRect: rect, xRadius: r, yRadius: r)
}

func fillDiagonal(_ path: NSBezierPath, _ a: NSColor, _ b: NSColor, angle: CGFloat) {
    NSGradient(starting: a, ending: b)!.draw(in: path, angle: angle)
}

func fillRadial(center: NSPoint, radius: CGFloat, color: NSColor) {
    guard let ctx = NSGraphicsContext.current?.cgContext else { return }
    ctx.saveGState()
    let colors = [color.cgColor, color.withAlphaComponent(0).cgColor] as CFArray
    guard let g = CGGradient(
        colorsSpace: NSColorSpace.deviceRGB.cgColorSpace,
        colors: colors, locations: [0, 1]
    ) else { ctx.restoreGState(); return }
    ctx.drawRadialGradient(
        g, startCenter: center, startRadius: 0,
        endCenter: center, endRadius: radius,
        options: [.drawsAfterEndLocation]
    )
    ctx.restoreGState()
}

func plate(_ tile: NSRect, c1: NSColor, c2: NSColor, angle: CGFloat,
           bloom: NSColor? = nil, shade: NSColor? = nil) {
    let S = tile.width
    let path = squircle(in: tile)
    fillDiagonal(path, c1, c2, angle: angle)
    NSGraphicsContext.saveGraphicsState()
    path.addClip()
    if let bloom {
        fillRadial(
            center: NSPoint(x: tile.minX + S * 0.28, y: tile.maxY - S * 0.22),
            radius: S * 0.75, color: bloom
        )
    }
    if let shade {
        fillRadial(
            center: NSPoint(x: tile.maxX - S * 0.18, y: tile.minY + S * 0.2),
            radius: S * 0.6, color: shade
        )
    }
    NSGraphicsContext.restoreGraphicsState()
}

func softShadow(_ path: NSBezierPath, blur: CGFloat, dy: CGFloat, alpha: CGFloat = 0.28) {
    NSGraphicsContext.saveGraphicsState()
    let sh = NSShadow()
    sh.shadowColor = NSColor(calibratedWhite: 0, alpha: alpha)
    sh.shadowBlurRadius = blur
    sh.shadowOffset = NSSize(width: 0, height: dy)
    sh.set()
    path.fill()
    NSGraphicsContext.restoreGraphicsState()
}

func slatePlate(_ tile: NSRect) {
    plate(tile,
          c1: NSColor(calibratedRed: 0.48, green: 0.53, blue: 0.60, alpha: 1),
          c2: NSColor(calibratedRed: 0.20, green: 0.24, blue: 0.30, alpha: 1),
          angle: 125,
          bloom: NSColor(calibratedWhite: 1, alpha: 0.12),
          shade: NSColor(calibratedWhite: 0, alpha: 0.26))
}

let creamHi = NSColor(calibratedRed: 0.99, green: 0.985, blue: 0.97, alpha: 1)
let creamLo = NSColor(calibratedRed: 0.90, green: 0.88, blue: 0.84, alpha: 1)
let inkSoft = NSColor(calibratedRed: 0.42, green: 0.40, blue: 0.36, alpha: 0.40)
let creamStroke = NSColor(calibratedRed: 0.97, green: 0.96, blue: 0.94, alpha: 1)

struct EnvelopeGeom {
    var body: NSBezierPath
    var ex: CGFloat
    var ey: CGFloat
    var ew: CGFloat
    var eh: CGFloat
    var r: CGFloat
    var g: CGFloat
}

func envelopeGeom(in tile: NSRect, scale: CGFloat = 1, dx: CGFloat = 0) -> EnvelopeGeom {
    let S = tile.width, g = S * 0.54 * scale
    let ew = g * 0.88, eh = g * 0.58
    let ex = tile.midX - ew / 2 + dx, ey = tile.midY - eh / 2
    let r = eh * 0.10
    let body = NSBezierPath(roundedRect: NSRect(x: ex, y: ey, width: ew, height: eh),
                            xRadius: r, yRadius: r)
    return EnvelopeGeom(body: body, ex: ex, ey: ey, ew: ew, eh: eh, r: r, g: g)
}

func paintEnvelope(_ e: EnvelopeGeom, pip: Bool) {
    let tileMidX = e.ex + e.ew / 2
    softShadow(e.body, blur: e.g * 0.06, dy: -e.g * 0.012)
    NSGradient(starting: creamHi, ending: creamLo)!.draw(in: e.body, angle: 90)

    NSGraphicsContext.saveGraphicsState()
    e.body.addClip()
    let flap = NSBezierPath()
    flap.move(to: NSPoint(x: e.ex - 1, y: e.ey + e.eh + 1))
    flap.line(to: NSPoint(x: tileMidX, y: e.ey + e.eh * 0.38))
    flap.line(to: NSPoint(x: e.ex + e.ew + 1, y: e.ey + e.eh + 1))
    flap.close()
    NSGradient(
        starting: NSColor(calibratedRed: 0.97, green: 0.95, blue: 0.92, alpha: 1),
        ending: NSColor(calibratedRed: 0.86, green: 0.83, blue: 0.78, alpha: 1)
    )!.draw(in: flap, angle: 90)

    let inset = e.r * 0.85
    let edge = NSBezierPath()
    edge.move(to: NSPoint(x: e.ex + inset, y: e.ey + e.eh - e.r * 0.15))
    edge.line(to: NSPoint(x: tileMidX, y: e.ey + e.eh * 0.40))
    edge.line(to: NSPoint(x: e.ex + e.ew - inset, y: e.ey + e.eh - e.r * 0.15))
    edge.lineWidth = max(0.9, e.g * 0.009)
    edge.lineCapStyle = .round
    edge.lineJoinStyle = .round
    inkSoft.setStroke()
    edge.stroke()

    if pip {
        let pipR = e.eh * 0.17
        let pip = NSBezierPath(ovalIn: NSRect(
            x: tileMidX - pipR,
            y: e.ey + e.eh * 0.36 - pipR,
            width: pipR * 2, height: pipR * 2
        ))
        creamHi.setFill()
        pip.fill()
        pip.lineWidth = max(0.8, e.g * 0.012)
        inkSoft.setStroke()
        pip.stroke()
    }
    NSGraphicsContext.restoreGraphicsState()
}

func paintPip(center: NSPoint, radius: CGFloat, g: CGFloat, ring: Bool) {
    let disk = NSBezierPath(ovalIn: NSRect(
        x: center.x - radius, y: center.y - radius,
        width: radius * 2, height: radius * 2
    ))
    softShadow(disk, blur: g * 0.05, dy: -g * 0.01)
    NSGradient(starting: creamHi, ending: creamLo)!.draw(in: disk, angle: 110)
    if ring {
        let ringPath = NSBezierPath(ovalIn: NSRect(
            x: center.x - radius * 1.28, y: center.y - radius * 1.28,
            width: radius * 2.56, height: radius * 2.56
        ))
        ringPath.lineWidth = max(1.2, g * 0.028)
        creamStroke.setStroke()
        ringPath.stroke()
    }
}

func drawCompanion(in tile: NSRect) {
    slatePlate(tile)
    paintEnvelope(envelopeGeom(in: tile), pip: true)
}

func drawPair(in tile: NSRect) {
    slatePlate(tile)
    let S = tile.width
    paintEnvelope(envelopeGeom(in: tile, scale: 0.90, dx: -S * 0.10), pip: false)
    let g = S * 0.54
    paintPip(
        center: NSPoint(x: tile.midX + S * 0.22, y: tile.midY - S * 0.02),
        radius: g * 0.13,
        g: g,
        ring: true
    )
}

func drawMono(in tile: NSRect) {
    slatePlate(tile)
    let S = tile.width, g = S * 0.56
    let stroke = max(2.6, g * 0.100)
    let c = NSPoint(x: tile.midX - g * 0.02, y: tile.midY)
    let radius = g * 0.30

    let arc = NSBezierPath()
    arc.appendArc(withCenter: c, radius: radius, startAngle: 38, endAngle: 322, clockwise: false)
    arc.lineWidth = stroke
    arc.lineCapStyle = .round

    let bar = NSBezierPath()
    bar.move(to: NSPoint(x: c.x, y: c.y))
    bar.line(to: NSPoint(x: c.x + radius * 0.96, y: c.y))
    bar.lineWidth = stroke * 0.72
    bar.lineCapStyle = .round

    NSGraphicsContext.saveGraphicsState()
    let sh = NSShadow()
    sh.shadowColor = NSColor(calibratedWhite: 0, alpha: 0.24)
    sh.shadowBlurRadius = g * 0.05
    sh.shadowOffset = NSSize(width: 0, height: -g * 0.01)
    sh.set()
    creamStroke.setStroke(); arc.stroke(); bar.stroke()
    NSGraphicsContext.restoreGraphicsState()
    creamStroke.setStroke(); arc.stroke(); bar.stroke()
}

func drawSeal(in tile: NSRect) {
    slatePlate(tile)
    let S = tile.width, g = S * 0.54
    let d = g * 0.78
    let disk = NSBezierPath(ovalIn: NSRect(
        x: tile.midX - d / 2, y: tile.midY - d / 2, width: d, height: d
    ))
    softShadow(disk, blur: g * 0.06, dy: -g * 0.012)
    NSGradient(starting: creamHi, ending: creamLo)!.draw(in: disk, angle: 110)

    let ring = NSBezierPath(ovalIn: NSRect(
        x: tile.midX - d * 0.42, y: tile.midY - d * 0.42,
        width: d * 0.84, height: d * 0.84
    ))
    ring.lineWidth = max(1.2, g * 0.018)
    NSColor(calibratedRed: 0.55, green: 0.52, blue: 0.48, alpha: 0.28).setStroke()
    ring.stroke()

    let arm = d * 0.28
    let drop = d * 0.22
    let cy = tile.midY + d * 0.08
    let flap = NSBezierPath()
    flap.move(to: NSPoint(x: tile.midX - arm, y: cy + drop * 0.2))
    flap.line(to: NSPoint(x: tile.midX, y: cy - drop))
    flap.line(to: NSPoint(x: tile.midX + arm, y: cy + drop * 0.2))
    flap.lineWidth = max(2.2, g * 0.048)
    flap.lineCapStyle = .round
    flap.lineJoinStyle = .round
    NSColor(calibratedRed: 0.38, green: 0.36, blue: 0.32, alpha: 0.55).setStroke()
    flap.stroke()

    let pipR = d * 0.09
    let pip = NSBezierPath(ovalIn: NSRect(
        x: tile.midX - pipR,
        y: cy - drop - pipR * 0.2,
        width: pipR * 2, height: pipR * 2
    ))
    NSColor(calibratedRed: 0.38, green: 0.36, blue: 0.32, alpha: 0.55).setFill()
    pip.fill()
}

func drawGlyph(design: Design, in tile: NSRect) {
    switch design {
    case .companion: drawCompanion(in: tile)
    case .pair: drawPair(in: tile)
    case .mono: drawMono(in: tile)
    case .seal: drawSeal(in: tile)
    }
}

func render(design: Design, px: Int) -> NSBitmapImageRep {
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
    let tile = NSRect(x: CGFloat(originPx), y: CGFloat(originPx),
                      width: CGFloat(tileSidePx), height: CGFloat(tileSidePx))
    squircle(in: tile).addClip()
    drawGlyph(design: design, in: tile)
    NSGraphicsContext.restoreGraphicsState()
    return rep
}

let args = Array(CommandLine.arguments.dropFirst())
var design: Design = .companion
var destArg: String?
var i = 0
while i < args.count {
    let a = args[i]
    if a == "--design", i + 1 < args.count {
        guard let d = Design.parse(args[i + 1]) else {
            fputs("Unknown design '\(args[i + 1])'. Use 1…\(Design.allCases.count) or name.\n", stderr)
            exit(2)
        }
        design = d
        i += 2
        continue
    }
    if a.hasPrefix("-") { fputs("Unknown flag \(a)\n", stderr); exit(2) }
    destArg = a
    i += 1
}

let scriptURL = URL(fileURLWithPath: CommandLine.arguments[0]).standardizedFileURL
let repoRoot = scriptURL.deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
let dest = destArg ?? repoRoot.appendingPathComponent("MailGent/Assets.xcassets/AppIcon.appiconset").path
try FileManager.default.createDirectory(atPath: dest, withIntermediateDirectories: true)

print("Generating AppIcon → \(dest)")
print("  design: \(design.label) — \(design.blurb)")
print(String(format: "  keyline ratio %.6f (824/1024)", Spec.keylineRatio))

for slot in Spec.macSizes {
    let rep = render(design: design, px: slot.pixels)
    let data = rep.representation(using: .png, properties: [:])!
    try data.write(to: URL(fileURLWithPath: dest).appendingPathComponent(slot.name))
    print(String(format: "  wrote %@ (%d px)", slot.name as NSString, slot.pixels))
}
print("done")
