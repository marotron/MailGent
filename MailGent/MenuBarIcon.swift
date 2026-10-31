import AppKit
import MailStore
import SwiftUI

enum PendingUserActionKind: Equatable, Sendable {
    case ask
    case proposeSend
}

struct PendingAskSummary: Equatable, Sendable {
    let id: String
    let agent: String
    let subject: String
    let kind: PendingUserActionKind
}

/// Concurrent human-action prompts (Ask + propose-send) in stable registration order.
struct PendingAskState: Equatable, Sendable {
    private(set) var summaries: [PendingAskSummary] = []
    private(set) var selectedID: String?

    var count: Int { summaries.count }

    mutating func register(
        id: String,
        agent: String,
        subject: String,
        kind: PendingUserActionKind = .ask
    ) {
        let trimmed = subject.trimmingCharacters(in: .whitespacesAndNewlines)
        summaries.append(
            PendingAskSummary(
                id: id,
                agent: agent,
                subject: trimmed.isEmpty ? "(no subject)" : trimmed,
                kind: kind
            )
        )
        if selectedID == nil {
            selectedID = id
        }
    }

    /// Raises one request in the list. Does not Allow or Block it.
    mutating func select(id: String) -> ConditionalAccessDecision? {
        guard summaries.contains(where: { $0.id == id }) else { return nil }
        selectedID = id
        return nil
    }

    /// Removes one request and returns the decision. A second call for the same id does nothing.
    mutating func resolve(id: String, with decision: ConditionalAccessDecision) -> ConditionalAccessDecision? {
        guard remove(id: id) else { return nil }
        return decision
    }

    /// Drops one pending request without an Allow/Block (e.g. rematch recheck).
    @discardableResult
    mutating func remove(id: String) -> Bool {
        guard let index = summaries.firstIndex(where: { $0.id == id }) else { return false }
        summaries.remove(at: index)
        if selectedID == id {
            selectedID = summaries.first?.id
        }
        return true
    }

    /// Traffic-light close is fail-closed Block for that request only.
    mutating func close(id: String) -> ConditionalAccessDecision? {
        resolve(id: id, with: .block)
    }
}

/// Status-menu pending human-actions section. Hidden when nothing is pending.
struct AccessRequestMenu: Equatable, Sendable {
    struct Row: Equatable, Sendable {
        let id: String
        let label: String
        let kind: PendingUserActionKind
        let isSelected: Bool
    }

    let isVisible: Bool
    let count: Int
    let rows: [Row]
    /// Spoken count, e.g. "1 item needs your action". Nil when the section is hidden.
    let accessibilityPhrase: String?

    static func project(_ state: PendingAskState) -> AccessRequestMenu {
        let rows = state.summaries.map { summary in
            Row(
                id: summary.id,
                label: rowLabel(summary),
                kind: summary.kind,
                isSelected: summary.id == state.selectedID
            )
        }
        return AccessRequestMenu(
            isVisible: state.count > 0,
            count: state.count,
            rows: rows,
            accessibilityPhrase: phrase(for: state.count)
        )
    }

    static func rowLabel(_ summary: PendingAskSummary) -> String {
        switch summary.kind {
        case .ask:
            return "\(summary.agent) · \(summary.subject)"
        case .proposeSend:
            return "\(summary.agent) · Send · \(summary.subject)"
        }
    }

    static func phrase(for count: Int) -> String? {
        switch count {
        case ..<1: return nil
        case 1: return "1 item needs your action"
        default: return "\(count) items need your action"
        }
    }
}

/// Pending human actions. Drives the menu section, menu-bar bubble, and Dock `badgeLabel`.
@MainActor
final class AskQueueIndicator: ObservableObject {
    static let shared = AskQueueIndicator()

    @Published private(set) var pending = PendingAskState()

    func register(
        id: String,
        agent: String,
        subject: String,
        kind: PendingUserActionKind = .ask
    ) {
        pending.register(id: id, agent: agent, subject: subject, kind: kind)
        syncDockBadge()
    }

    @discardableResult
    func select(id: String) -> ConditionalAccessDecision? {
        pending.select(id: id)
    }

    @discardableResult
    func resolve(id: String, with decision: ConditionalAccessDecision) -> ConditionalAccessDecision? {
        let applied = pending.resolve(id: id, with: decision)
        if applied != nil { syncDockBadge() }
        return applied
    }

    @discardableResult
    func remove(id: String) -> Bool {
        let removed = pending.remove(id: id)
        if removed { syncDockBadge() }
        return removed
    }

    private func syncDockBadge() {
        let count = pending.count
        NSApp.dockTile.badgeLabel = count > 0 ? Self.badgeText(count) : nil
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
        let askDepth = askQueue.pending.count
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
        guard let phrase = AccessRequestMenu.phrase(for: askDepth) else {
            return appearance.accessibilityLabel
        }
        return "\(appearance.accessibilityLabel), \(phrase)"
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
