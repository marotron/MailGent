import AppKit
import SwiftUI

enum MenuBarIconKind: Equatable, Sendable {
    case idle
    case success
    case error
}

/// Status-item pulse: success and error linger so a fast MCP call stays visible.
struct MenuBarIconPulse: Equatable, Sendable {
    static let successHold: TimeInterval = 3
    static let errorHold: TimeInterval = 6

    private(set) var kind: MenuBarIconKind = .idle
    private var expiresAt: Date?

    mutating func recordSuccess(at date: Date = Date()) {
        kind = .success
        expiresAt = date.addingTimeInterval(Self.successHold)
    }

    mutating func recordError(at date: Date = Date()) {
        kind = .error
        expiresAt = date.addingTimeInterval(Self.errorHold)
    }

    mutating func clear() {
        kind = .idle
        expiresAt = nil
    }

    func kind(at now: Date) -> MenuBarIconKind {
        guard kind != .idle, let expiresAt, now < expiresAt else {
            return .idle
        }
        return kind
    }
}

struct MenuBarIconLabel: View {
    @Bindable var agents: AgentBridge

    var body: some View {
        let kind = agents.iconPulse.kind
        Image(nsImage: Self.image(kind))
            .id(kind)
            .accessibilityLabel("MailGent")
    }

    private static func image(_ kind: MenuBarIconKind) -> NSImage {
        let name: String
        switch kind {
        case .idle: name = "tray.full"
        case .success: name = "tray.full.fill"
        case .error: name = "exclamationmark.triangle.fill"
        }
        let base = NSImage(systemSymbolName: name, accessibilityDescription: "MailGent")
            ?? NSImage(size: NSSize(width: 18, height: 18))
        let size = NSImage.SymbolConfiguration(pointSize: 16, weight: .medium)
        switch kind {
        case .idle:
            let image = base.withSymbolConfiguration(size) ?? base
            image.isTemplate = true
            return image
        case .success, .error:
            let color: NSColor = kind == .success ? .systemGreen : .systemOrange
            let tinted = size.applying(.init(paletteColors: [color]))
            let image = base.withSymbolConfiguration(tinted) ?? base
            image.isTemplate = false
            return image
        }
    }
}
