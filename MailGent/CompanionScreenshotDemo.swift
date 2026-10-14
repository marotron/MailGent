import Foundation

// =============================================================================
// SCREENSHOT_DEMO_POLICY — DEBUG only. Local capture helper; Release CI strips it.
// See CompanionDemoPolicy.swift.
// =============================================================================

#if DEBUG

enum CompanionScreenshotDemo {
    /// `MAILGENT_SCREENSHOT_SCENE` values for CI / `screenshots.sh --ci`.
    enum Scene: String, CaseIterable {
        case controlCenter = "control-center"
        case grantDeskScope = "grant-desk-scope"
        case grantDeskAccess = "grant-desk-access"
        case grantDeskRules = "grant-desk-rules"
        case grantDeskPrivacy = "grant-desk-privacy"

        var opensCompanion: Bool { self == .controlCenter }
        var opensGrantDesk: Bool { self != .controlCenter }

        var windowTitle: String {
            switch self {
            case .controlCenter: "MailGent"
            case .grantDeskScope, .grantDeskAccess, .grantDeskRules, .grantDeskPrivacy:
                "Grant desk"
            }
        }

        var outputBasename: String { rawValue }
    }

    /// Shared with `Scripts/release/screenshots.sh` (must match path there).
    static var readyMarkerURL: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("MailGent", isDirectory: true)
            .appendingPathComponent("mailgent-screenshot-ready", isDirectory: false)
    }

    static func sceneFromEnvironment() -> Scene? {
        guard let raw = ProcessInfo.processInfo.environment["MAILGENT_SCREENSHOT_SCENE"],
              !raw.isEmpty
        else { return nil }
        return Scene(rawValue: raw)
    }

    static func clearReadyMarker() {
        try? FileManager.default.removeItem(at: readyMarkerURL)
    }

    static func writeReadyMarker(scene: Scene) {
        let dir = readyMarkerURL.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let body = "\(scene.rawValue)\n"
        try? body.write(to: readyMarkerURL, atomically: true, encoding: .utf8)
    }
}

#endif
