#!/usr/bin/env swift
// Renders export.html → background.png for the Finder DMG window.
//
// Logical size is measured from #canvas (fit content).
// On Retina, Finder draws the background at 1 CSS-px ≈ 2 device-px, so the
// PNG must be 2× @ 144 DPI — a 1× PNG appears at ~¼ size.
//
// Usage: swift Scripts/release/dmg-assets/render-background.swift
import AppKit
import Foundation
import WebKit

final class Renderer: NSObject, WKNavigationDelegate {
  /// Large enough that fit-content export.html can lay out fully before measure.
  let frameW: CGFloat = 900
  let frameH: CGFloat = 900
  let scale: CGFloat = 2

  let webView: WKWebView
  let outURL: URL
  private var finished = false

  init(htmlURL: URL, outURL: URL) {
    self.outURL = outURL
    let wv = WKWebView(
      frame: NSRect(x: 0, y: 0, width: frameW, height: frameH),
      configuration: WKWebViewConfiguration()
    )
    wv.setValue(false, forKey: "drawsBackground")
    self.webView = wv
    super.init()
    wv.navigationDelegate = self
    wv.loadFileURL(htmlURL, allowingReadAccessTo: htmlURL.deletingLastPathComponent())
  }

  private func finish(code: Int32, message: String? = nil) {
    guard !finished else { return }
    finished = true
    if let message {
      fputs(message, stderr)
    }
    exit(code)
  }

  func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
    DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
      let measureJS = """
        (() => {
          const canvas = document.getElementById('canvas');
          const r = canvas.getBoundingClientRect();
          const w = Math.ceil(r.width);
          const h = Math.ceil(r.height);
          const slots = Array.from(document.querySelectorAll('[data-slot]')).map(el => {
            const sr = el.getBoundingClientRect();
            return el.dataset.slot + ' ' + Math.round(sr.left + sr.width/2) + ' ' + Math.round(sr.top + sr.height/2);
          }).join('\\n');
          return JSON.stringify({ w, h, slots });
        })()
        """
      webView.evaluateJavaScript(measureJS) { result, error in
        if let error {
          self.finish(code: 1, message: "error: measure failed: \(error)\n")
          return
        }
        guard let json = result as? String,
              let data = json.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let widthNum = obj["w"] as? NSNumber,
              let heightNum = obj["h"] as? NSNumber else {
          self.finish(code: 1, message: "error: could not measure canvas size\n")
          return
        }
        let logicalW = CGFloat(truncating: widthNum)
        let logicalH = CGFloat(truncating: heightNum)
        guard logicalW > 0, logicalH > 0 else {
          self.finish(code: 1, message: "error: canvas size is zero\n")
          return
        }
        if let slots = obj["slots"] as? String, !slots.isEmpty {
          fputs("icon-slot centers (for dmg.sh):\n\(slots)\n", stderr)
        }
        fputs("canvas size: \(Int(logicalW))×\(Int(logicalH)) logical\n", stderr)

        let pixelW = Int(logicalW * self.scale)
        let pixelH = Int(logicalH * self.scale)

        let config = WKSnapshotConfiguration()
        config.rect = NSRect(x: 0, y: 0, width: logicalW, height: logicalH)
        if #available(macOS 10.15, *) {
          config.snapshotWidth = NSNumber(value: Double(logicalW * self.scale))
        }
        webView.takeSnapshot(with: config) { image, error in
          if let error {
            self.finish(code: 1, message: "error: \(error)\n")
            return
          }
          guard let image else {
            self.finish(code: 1, message: "error: empty snapshot\n")
            return
          }

          let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: pixelW,
            pixelsHigh: pixelH,
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
          )!
          rep.size = NSSize(width: logicalW, height: logicalH)
          NSGraphicsContext.saveGraphicsState()
          NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
          image.draw(
            in: NSRect(x: 0, y: 0, width: logicalW, height: logicalH),
            from: .zero,
            operation: .copy,
            fraction: 1
          )
          NSGraphicsContext.restoreGraphicsState()

          guard let png = rep.representation(using: .png, properties: [:]) else {
            self.finish(code: 1, message: "error: Failed to encode PNG\n")
            return
          }
          do {
            let tmp = self.outURL.deletingLastPathComponent()
              .appendingPathComponent("background-raw.png")
            try png.write(to: tmp)

            let sipsSize = Process()
            sipsSize.executableURL = URL(fileURLWithPath: "/usr/bin/sips")
            sipsSize.arguments = [
              "-z", "\(pixelH)", "\(pixelW)",
              tmp.path,
              "--out", self.outURL.path,
            ]
            try sipsSize.run()
            sipsSize.waitUntilExit()

            let sipsDpi = Process()
            sipsDpi.executableURL = URL(fileURLWithPath: "/usr/bin/sips")
            sipsDpi.arguments = [
              "-s", "dpiWidth", "144",
              "-s", "dpiHeight", "144",
              self.outURL.path,
            ]
            try sipsDpi.run()
            sipsDpi.waitUntilExit()

            try? FileManager.default.removeItem(at: tmp)
            guard sipsSize.terminationStatus == 0,
                  sipsDpi.terminationStatus == 0,
                  FileManager.default.fileExists(atPath: self.outURL.path) else {
              self.finish(code: 1, message: "error: sips failed to finalize background\n")
              return
            }
            fputs(
              "Wrote \(self.outURL.path) (\(pixelW)×\(pixelH) @ 144 DPI = \(Int(logicalW))×\(Int(logicalH)) logical)\n",
              stderr
            )
            fputs(
              "Set dmg.sh WIN_W=\(Int(logicalW)) WIN_H=\(Int(logicalH) + 28)\n",
              stderr
            )
            self.finish(code: 0)
          } catch {
            self.finish(code: 1, message: "error: \(error)\n")
          }
        }
      }
    }
  }

  func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
    finish(code: 1, message: "error: \(error)\n")
  }

  func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
    finish(code: 1, message: "error: \(error)\n")
  }
}

let dir = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
let htmlURL = dir.appendingPathComponent("export.html")
let outURL = dir.appendingPathComponent("background.png")

guard FileManager.default.fileExists(atPath: htmlURL.path) else {
  fputs("error: missing \(htmlURL.path)\n", stderr)
  exit(1)
}

let app = NSApplication.shared
app.setActivationPolicy(.accessory)

let renderer = Renderer(htmlURL: htmlURL, outURL: outURL)
withExtendedLifetime(renderer) {
  DispatchQueue.main.asyncAfter(deadline: .now() + 30) {
    fputs("error: timed out waiting for WKWebView snapshot\n", stderr)
    exit(1)
  }
  app.run()
}
