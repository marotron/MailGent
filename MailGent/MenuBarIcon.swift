import AppKit
import MailStore
import SwiftUI

/// Pending Ask prompts (open dialog + queued). Drives menu-bar bubble and Dock `badgeLabel`.
@MainActor
final class AskQueueIndicator: ObservableObject {
    static let shared = AskQueueIndicator()

    @Published private(set) var depth: Int = 0

    func setDepth(_ depth: Int) {
        let next = max(0, depth)
        guard self.depth != next else { return }
        self.depth = next
        NSApp.dockTile.badgeLabel = next > 0 ? Self.badgeText(next) : nil
        NSApp.dockTile.display()
    }

    static func badgeText(_ count: Int) -> String {
        count > 99 ? "99+" : "\(count)"
    }
}

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
    @ObservedObject private var askQueue = AskQueueIndicator.shared

    var body: some View {
        let appearance = MenuBarIconAppearance.resolve(source: source, pulse: agents.iconPulse.kind)
        let askDepth = askQueue.depth
        ZStack(alignment: .topTrailing) {
            Image(nsImage: Self.image(appearance))
            if askDepth > 0 {
                Text(AskQueueIndicator.badgeText(askDepth))
                    .font(.system(size: 8, weight: .bold))
                    .monospacedDigit()
                    .foregroundStyle(.white)
                    .padding(.horizontal, askDepth > 9 ? 2.5 : 0)
                    .frame(minWidth: 11, minHeight: 11)
                    .background(Capsule().fill(Color.red))
                    .offset(x: 5, y: -3)
            }
        }
        .id("\(source.rawValue)-\(agents.iconPulse.kind)-\(askDepth)")
        .accessibilityLabel(Self.accessibilityLabel(appearance: appearance, askDepth: askDepth))
    }

    private static func accessibilityLabel(appearance: MenuBarIconAppearance, askDepth: Int) -> String {
        guard askDepth > 0 else { return appearance.accessibilityLabel }
        let asks = askDepth == 1 ? "1 Ask pending" : "\(askDepth) Asks pending"
        return "\(appearance.accessibilityLabel), \(asks)"
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
