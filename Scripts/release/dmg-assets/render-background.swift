#!/usr/bin/env swift
// Renders export.html → background.png for the Finder DMG window.
//
// Logical canvas is 460×412 (matches icon coords / window content).
// On Retina, Finder draws the background at 1 CSS-px ≈ 2 device-px, so the
// PNG must be 2× (920×824) @ 144 DPI — a 1× PNG appears at ~¼ size.
//
// Usage: swift Scripts/release/dmg-assets/render-background.swift
import AppKit
import Foundation
import WebKit

final class Renderer: NSObject, WKNavigationDelegate {
  let logicalW: CGFloat = 460
  let logicalH: CGFloat = 412
  let scale: CGFloat = 2
  var pixelW: Int { Int(logicalW * scale) }
  var pixelH: Int { Int(logicalH * scale) }

  let webView: WKWebView
  let outURL: URL
  private var finished = false

  init(htmlURL: URL, outURL: URL) {
    self.outURL = outURL
    let wv = WKWebView(
      frame: NSRect(x: 0, y: 0, width: logicalW, height: logicalH),
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
        Array.from(document.querySelectorAll('[data-slot]')).map(el => {
          const r = el.getBoundingClientRect();
          return el.dataset.slot + ' ' + Math.round(r.left + r.width/2) + ' ' + Math.round(r.top + r.height/2);
        }).join('\\n');
        """
      webView.evaluateJavaScript(measureJS) { result, _ in
        if let text = result as? String, !text.isEmpty {
          fputs("icon-slot centers (for dmg.sh):\n\(text)\n", stderr)
        }

        let config = WKSnapshotConfiguration()
        config.rect = NSRect(x: 0, y: 0, width: self.logicalW, height: self.logicalH)
        // Prefer an explicit 2× snapshot so output is stable across displays.
        if #available(macOS 10.15, *) {
          config.snapshotWidth = NSNumber(value: Double(self.logicalW * self.scale))
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

          // Rasterize into an exact 920×824 bitmap (Finder Retina background).
          let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: self.pixelW,
            pixelsHigh: self.pixelH,
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
          )!
          rep.size = NSSize(width: self.logicalW, height: self.logicalH)
          NSGraphicsContext.saveGraphicsState()
          NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
          image.draw(
            in: NSRect(x: 0, y: 0, width: self.logicalW, height: self.logicalH),
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

            // Force pixel size + 144 DPI so Finder treats it as a 2× Retina asset.
            let sipsSize = Process()
            sipsSize.executableURL = URL(fileURLWithPath: "/usr/bin/sips")
            sipsSize.arguments = [
              "-z", "\(self.pixelH)", "\(self.pixelW)",
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
              "Wrote \(self.outURL.path) (\(self.pixelW)×\(self.pixelH) @ 144 DPI = \(Int(self.logicalW))×\(Int(self.logicalH)) logical)\n",
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
