#!/usr/bin/env swift
// SCREENSHOT_DEMO_POLICY — remove with CompanionDemoPolicy.swift
// Captures an on-screen window whose title contains the given substring.
import Cocoa
import Foundation

guard CommandLine.arguments.count >= 3 else {
    fputs("usage: capture-named-window.swift <title-substring> <out.png>\n", stderr)
    exit(2)
}

let needle = CommandLine.arguments[1]
let outPath = CommandLine.arguments[2]
let options = CGWindowListOption(arrayLiteral: .optionOnScreenOnly, .excludeDesktopElements)
guard let info = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] else {
    fputs("error: CGWindowListCopyWindowInfo failed\n", stderr)
    exit(1)
}

struct Hit {
    let id: CGWindowID
    let title: String
    let area: Int
}

var hits: [Hit] = []
for entry in info {
    guard let title = entry[kCGWindowName as String] as? String,
          title.localizedCaseInsensitiveContains(needle)
    else { continue }
    guard let number = entry[kCGWindowNumber as String] as? NSNumber else { continue }
    let bounds = entry[kCGWindowBounds as String] as? [String: Any]
    let width = (bounds?["Width"] as? NSNumber)?.intValue ?? 0
    let height = (bounds?["Height"] as? NSNumber)?.intValue ?? 0
    hits.append(Hit(id: CGWindowID(number.uint32Value), title: title, area: width * height))
}

guard let best = hits.max(by: { $0.area < $1.area }) else {
    fputs("error: no on-screen window matching \"\(needle)\"\n", stderr)
    exit(1)
}

let process = Process()
process.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
process.arguments = ["-x", "-l\(best.id)", outPath]
try process.run()
process.waitUntilExit()
if process.terminationStatus != 0 {
    fputs("error: screencapture failed status=\(process.terminationStatus) window=\(best.id) title=\(best.title)\n", stderr)
    exit(process.terminationStatus)
}

fputs("captured \"\(best.title)\" (id=\(best.id)) → \(outPath)\n", stderr)
