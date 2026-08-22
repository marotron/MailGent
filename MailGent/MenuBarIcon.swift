import AppKit
import MailStore
import SwiftUI

enum MenuBarIconKind: Equatable, Sendable {
    case idle
    case success
    case error
}

struct MenuBarIconAppearance: Equatable, Sendable {
    enum Tint: Equatable, Sendable {
        case menuBar
        case success
        case error
        case fixture
    }

    let symbolName: String
    let tint: Tint
    let accessibilityLabel: String

    var isTemplate: Bool { tint == .menuBar }

    static func resolve(source: MailSourceID, pulse: MenuBarIconKind) -> MenuBarIconAppearance {
        if pulse == .error {
            return MenuBarIconAppearance(
                symbolName: "exclamationmark.triangle.fill",
                tint: .error,
                accessibilityLabel: source == .fixture ? "MailGent fixture mail" : "MailGent"
            )
        }
        if source == .fixture {
            return MenuBarIconAppearance(
                symbolName: "theatermasks.fill",
                tint: pulse == .success ? .success : .fixture,
                accessibilityLabel: "MailGent fixture mail"
            )
        }
        switch pulse {
        case .idle:
            return MenuBarIconAppearance(
                symbolName: "tray.full",
                tint: .menuBar,
                accessibilityLabel: "MailGent"
            )
        case .success:
            return MenuBarIconAppearance(
                symbolName: "tray.full.fill",
                tint: .success,
                accessibilityLabel: "MailGent"
            )
        case .error:
            return MenuBarIconAppearance(
                symbolName: "exclamationmark.triangle.fill",
                tint: .error,
                accessibilityLabel: "MailGent"
            )
        }
    }
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
    var source: MailSourceID

    var body: some View {
        let appearance = MenuBarIconAppearance.resolve(source: source, pulse: agents.iconPulse.kind)
        Image(nsImage: Self.image(appearance))
            .id("\(source.rawValue)-\(agents.iconPulse.kind)")
            .accessibilityLabel(appearance.accessibilityLabel)
    }

    private static func image(_ appearance: MenuBarIconAppearance) -> NSImage {
        let base = NSImage(systemSymbolName: appearance.symbolName, accessibilityDescription: appearance.accessibilityLabel)
            ?? NSImage(size: NSSize(width: 18, height: 18))
        let size = NSImage.SymbolConfiguration(pointSize: 16, weight: .medium)
        switch appearance.tint {
        case .menuBar:
            let image = base.withSymbolConfiguration(size) ?? base
            image.isTemplate = true
            return image
        case .success, .error, .fixture:
            let color: NSColor
            switch appearance.tint {
            case .success: color = .systemGreen
            case .error: color = .systemOrange
            case .fixture: color = .systemPurple
            case .menuBar: color = .labelColor
            }
            let tinted = size.applying(.init(paletteColors: [color]))
            let image = base.withSymbolConfiguration(tinted) ?? base
            image.isTemplate = false
            return image
        }
    }
}
