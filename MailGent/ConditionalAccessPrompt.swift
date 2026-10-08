import AppKit
import Foundation
import MailStore
import SwiftUI

/// Request to prompt user for conditional field access.
public struct ConditionalAccessPromptRequest: Identifiable, Sendable {
    public let id: String
    public let context: ConditionalAccessPromptContext

    public var agentName: String { context.agentName }
    public var accountID: String { context.accountID }
    public var placement: String { context.placement }
    public var requestedFields: [String] { context.requestedFields }
    public var fieldPreviews: [ConditionalFieldPreviewLine] { context.fieldPreviews }

    public init(
        id: String = UUID().uuidString,
        context: ConditionalAccessPromptContext
    ) {
        self.id = id
        self.context = context
    }
}

/// Coordinator for showing conditional access prompts and waiting for user decisions.
/// Lives on AgentBridge (main actor) and is called from MCP get via MainActor hop.
///
/// Presents via `DetachedWindowHost.runConditionalAsk` (HostedWindow) so MenuBarExtra
/// hide / orderOut cannot flash-dismiss the Ask dialog or other MailGent windows.
@MainActor
public final class ConditionalAccessPromptCoordinator: ObservableObject {
    @Published public var pendingRequest: ConditionalAccessPromptRequest?

    public init() {}

    /// Request a decision from the user. Suspends until Allow / Block.
    /// Always returns (never throws); Block is fail-closed.
    public func requestDecision(
        context: ConditionalAccessPromptContext,
        accountLabel: String? = nil
    ) async -> ConditionalAccessDecision {
        let request = ConditionalAccessPromptRequest(context: context)
        pendingRequest = request

        let mailboxLabel = accountLabel.flatMap { $0.isEmpty ? nil : $0 } ?? context.accountID
        let fieldsText = context.requestedFields.joined(separator: ", ")

        let decision = await DetachedWindowHost.shared.runConditionalAsk(
            request: request,
            accountLabel: mailboxLabel
        )

        if pendingRequest?.id == request.id {
            pendingRequest = nil
        }
        MailGentLog.trace(
            "conditional access \(decision == .allow ? "allow" : "block") agent=\(context.agentName) fields=\(fieldsText)"
        )
        return decision
    }

    /// User chose Allow (SwiftUI path, if any).
    public func allow() {
        pendingRequest = nil
    }

    /// User chose Block or dismissed (SwiftUI path, if any).
    public func block() {
        pendingRequest = nil
    }
}

enum ConditionalAskLayout {
    static let pad: CGFloat = 12
    static let gap: CGFloat = 12
    static let cardRadius: CGFloat = 8
    /// Default / ideal left pane (a bit wider than the first compact pass).
    static let leftColumnWidth: CGFloat = 360
    static let leftColumnMinWidth: CGFloat = 300
    static let leftColumnMaxWidth: CGFloat = 520
    static let previewColumnWidth: CGFloat = 460
    static let previewColumnMinWidth: CGFloat = 320
    static let dialogHeight: CGFloat = 520
    static let dialogMinHeight: CGFloat = 420
    /// Non-body long-field collapsed / expanded preview heights.
    static let fieldPreviewCollapsedHeight: CGFloat = 64
    static let fieldPreviewExpandedHeight: CGFloat = 200
    /// Body card must keep at least this much text area when the window is short.
    static let bodyPreviewMinHeight: CGFloat = 120
    /// Breathing room between left cards and the HSplitView divider.
    static let splitTrailingGap: CGFloat = 10

    static var compactWidth: CGFloat { leftColumnWidth + pad * 2 }
    static var expandedWidth: CGFloat {
        leftColumnWidth + gap + previewColumnWidth + pad * 2
    }

    static func contentSize(previewVisible: Bool) -> NSSize {
        NSSize(
            width: previewVisible ? expandedWidth : compactWidth,
            height: dialogHeight
        )
    }

    static func minContentSize(previewVisible: Bool) -> NSSize {
        NSSize(
            width: previewVisible
                ? leftColumnMinWidth + gap + previewColumnMinWidth + pad * 2
                : leftColumnMinWidth + pad * 2,
            height: dialogMinHeight
        )
    }
}

/// In-app Preview content — Companion `MessageBodyView` (HTML via WKWebView).
/// Entire message only (not Ask-field chips); fills the right-hand pane.
struct ConditionalAccessInAppPreview: View {
    let context: ConditionalAccessPromptContext

    private var hasHTML: Bool {
        guard let html = context.htmlBody else { return false }
        return !html.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var plainFallback: ReadBody {
        if let bodyLine = context.fieldPreviews.first(where: { $0.label == "Body" }) {
            let value = bodyLine.value
            if value == "(empty)" { return .text("") }
            return .text(value)
        }
        return .notAvailable
    }

    var body: some View {
        Group {
            if hasHTML || context.fieldPreviews.contains(where: { $0.label == "Body" }) {
                MessageBodyView(
                    // Empty plain when HTML exists so MessageBodyView does not discard HTML
                    // via the closed-prefix heuristic against Ask field text.
                    readBody: hasHTML ? .text("") : plainFallback,
                    htmlBody: context.htmlBody
                )
            } else {
                Text("(no message body to preview)")
                    .foregroundStyle(.secondary)
                    .italic()
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

/// SwiftUI view for the conditional access prompt dialog (previews / optional hosts).
struct ConditionalAccessPromptDialog: View {
    let request: ConditionalAccessPromptRequest
    let accountLabel: String
    let onAllow: () -> Void
    let onBlock: () -> Void
    var showOpenInMail: Bool = false
    var onOpenInMail: (() -> Void)? = nil
    /// Outer inset; off when a parent owns the padding.
    var chromePadding: Bool = true
    /// When false, hide the right-hand rendered message pane (Xcode canvas left-only).
    var showsMessagePreview: Bool = true
    /// Host resizes the Ask window when Preview toggles.
    var onPreviewVisibilityChange: ((Bool) -> Void)? = nil

    @State private var messagePreviewVisible: Bool = true
    @State private var hoveringIdentity = false

    private var envelope: ConditionalMessageEnvelope { request.context.envelope }

    private var accountIDLooksLikeLabel: Bool {
        accountLabel.caseInsensitiveCompare(request.accountID) == .orderedSame
    }

    var body: some View {
        Group {
            if showsMessagePreview, messagePreviewVisible {
                HSplitView {
                    leftColumn
                        .padding(.trailing, ConditionalAskLayout.splitTrailingGap)
                        .frame(
                            minWidth: ConditionalAskLayout.leftColumnMinWidth,
                            idealWidth: ConditionalAskLayout.leftColumnWidth,
                            maxWidth: ConditionalAskLayout.leftColumnMaxWidth
                        )
                    messagePreviewColumn
                        .padding(.leading, ConditionalAskLayout.splitTrailingGap)
                        .frame(
                            minWidth: ConditionalAskLayout.previewColumnMinWidth,
                            idealWidth: ConditionalAskLayout.previewColumnWidth,
                            maxWidth: .infinity
                        )
                }
            } else {
                leftColumn
                    .frame(
                        minWidth: ConditionalAskLayout.leftColumnMinWidth,
                        idealWidth: ConditionalAskLayout.leftColumnWidth,
                        maxWidth: .infinity
                    )
            }
        }
        .padding(chromePadding ? ConditionalAskLayout.pad : 0)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .onAppear {
            messagePreviewVisible = showsMessagePreview
            onPreviewVisibilityChange?(messagePreviewVisible && showsMessagePreview)
        }
    }

    private var bodyFieldPreview: ConditionalFieldPreviewLine? {
        request.fieldPreviews.first { $0.label == "Body" }
    }

    private var preBodyFieldPreviews: [ConditionalFieldPreviewLine] {
        guard let bodyIndex = request.fieldPreviews.firstIndex(where: { $0.label == "Body" }) else {
            return request.fieldPreviews
        }
        return Array(request.fieldPreviews.prefix(bodyIndex))
    }

    private var postBodyFieldPreviews: [ConditionalFieldPreviewLine] {
        guard let bodyIndex = request.fieldPreviews.firstIndex(where: { $0.label == "Body" }) else {
            return []
        }
        return Array(request.fieldPreviews.suffix(from: bodyIndex + 1))
    }

    private var leftColumn: some View {
        VStack(alignment: .leading, spacing: ConditionalAskLayout.gap) {
            HStack(alignment: .top, spacing: ConditionalAskLayout.gap) {
                Image(systemName: "questionmark.circle.fill")
                    .font(.system(size: 18))
                    .foregroundStyle(.orange)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Field Access Request")
                        .font(.headline)
                    Text(
                        "This agent’s grant is set to Ask for the fields below. Allow shares them for this read only; Block keeps them withheld."
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                }
            }

            // Message + non-body cards keep intrinsic height; Body fills the rest.
            VStack(alignment: .leading, spacing: ConditionalAskLayout.gap) {
                messageCard

                if request.fieldPreviews.isEmpty {
                    ConditionalAskCard {
                        Text("(no field preview available)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .italic()
                    }
                } else {
                    ForEach(preBodyFieldPreviews, id: \.label) { line in
                        ConditionalAskFieldPreviewCard(line: line)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    if let bodyFieldPreview {
                        ConditionalAskFieldPreviewCard(line: bodyFieldPreview, fillsAvailableHeight: true)
                            .frame(
                                maxWidth: .infinity,
                                minHeight: ConditionalAskLayout.bodyPreviewMinHeight,
                                maxHeight: .infinity,
                                alignment: .topLeading
                            )
                            .layoutPriority(1)
                    }
                    // Attachment / other cards hug content; Body stays the tall flex card.
                    ForEach(postBodyFieldPreviews, id: \.label) { line in
                        ConditionalAskFieldPreviewCard(line: line)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)

            HStack(spacing: ConditionalAskLayout.gap) {
                Button("Block") {
                    onBlock()
                }
                .keyboardShortcut(.cancelAction)

                Spacer()

                Button("Allow") {
                    onAllow()
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var messageCard: some View {
        ConditionalAskCard {
            VStack(alignment: .leading, spacing: ConditionalAskLayout.gap / 2) {
                identityLine

                Divider().opacity(0.35)

                HStack(spacing: 6) {
                    Image(systemName: "envelope")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Text("Message")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Spacer(minLength: 4)
                    if showsMessagePreview {
                        SecondaryActionButton(
                            title: "Preview",
                            systemImage: "eye",
                            alwaysExpanded: true
                        ) {
                            togglePreview()
                        }
                    }
                    if showOpenInMail, let onOpenInMail {
                        SecondaryActionButton(
                            title: "Open in Apple Mail",
                            alwaysExpanded: true
                        ) {
                            onOpenInMail()
                        } icon: {
                            OpenInMailGlyph()
                        }
                    }
                }

                envelopeRow(label: "Subject", value: envelope.subject)
                envelopeAddressRow(label: "From", raw: envelope.from)
                if !envelope.to.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    envelopeAddressRow(label: "To", raw: envelope.to)
                }
                if !envelope.cc.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    envelopeAddressRow(label: "Cc", raw: envelope.cc)
                }
                envelopeRow(label: "Date", value: envelope.date)

                Divider().opacity(0.35)

                HStack(alignment: .center, spacing: 6) {
                    Text("Ask")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    FlowFieldChips(labels: request.requestedFields)
                }
            }
        }
    }

    private var identityLine: some View {
        HStack(spacing: 6) {
            Text(request.agentName)
                .font(.caption.weight(.semibold))
                .textSelection(.enabled)
            Text("·")
                .foregroundStyle(.tertiary)
            if hoveringIdentity {
                Text(request.accountID)
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
                    .lineLimit(1)
                Text("/")
                    .foregroundStyle(.tertiary)
            } else if !accountIDLooksLikeLabel {
                Text(accountLabel)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
                    .lineLimit(1)
                Text("/")
                    .foregroundStyle(.tertiary)
            }
            Text(request.placement)
                .font(.caption)
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
                .lineLimit(1)
        }
        .contentShape(Rectangle())
        .onHover { hovering in
            hoveringIdentity = hovering
        }
        .help("Account ID: \(request.accountID)")
    }

    private var messagePreviewColumn: some View {
        ConditionalAccessInAppPreview(context: request.context)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func togglePreview() {
        let next = !messagePreviewVisible
        withAnimation(SecondaryActionMetrics.expandAnimation) {
            messagePreviewVisible = next
        }
        onPreviewVisibilityChange?(next)
    }

    private static let envelopeLabelWidth: CGFloat = 52

    private func envelopeLabel(_ label: String) -> some View {
        Text(label)
            .font(.caption2)
            .foregroundStyle(.secondary)
            .frame(width: Self.envelopeLabelWidth, alignment: .leading)
            .textSelection(.enabled)
    }

    private func envelopeRow(label: String, value: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            envelopeLabel(label)
            Text(value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "—" : value)
                .font(.caption2)
                .textSelection(.enabled)
                .lineLimit(3)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func envelopeAddressRow(label: String, raw: String) -> some View {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        let addresses = MailAddressParts.parseList(trimmed)
        return HStack(alignment: .firstTextBaseline, spacing: 8) {
            envelopeLabel(label)
            if trimmed.isEmpty {
                Text("—")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            } else if addresses.isEmpty {
                Text(trimmed)
                    .font(.caption2)
                    .textSelection(.enabled)
                    .lineLimit(3)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                FlowAddressBadges(addresses: addresses)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }
}

/// Wraps name + grey email badges onto following lines when the pane is narrow.
private struct FlowAddressBadges: View {
    let addresses: [MailAddressParts]

    var body: some View {
        // Simple wrapping HStack is enough for Ask’s typical 1–2 recipients.
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            ForEach(Array(addresses.enumerated()), id: \.offset) { _, parts in
                HStack(spacing: 6) {
                    if let name = parts.name {
                        Text(name)
                            .font(.caption2)
                            .textSelection(.enabled)
                    }
                    if let email = parts.email {
                        AddressBadge(email: email)
                            .font(.caption2)
                    }
                }
            }
            Spacer(minLength: 0)
        }
    }
}

private struct ConditionalAskCard<Content: View>: View {
    var fillsHeight: Bool = false
    @ViewBuilder let content: Content

    var body: some View {
        content
            .padding(ConditionalAskLayout.pad)
            .frame(
                maxWidth: .infinity,
                maxHeight: fillsHeight ? .infinity : nil,
                alignment: .topLeading
            )
            .background(
                RoundedRectangle(cornerRadius: ConditionalAskLayout.cardRadius, style: .continuous)
                    .fill(Color.secondary.opacity(0.06))
            )
            .clipShape(
                RoundedRectangle(cornerRadius: ConditionalAskLayout.cardRadius, style: .continuous)
            )
    }
}

/// One Ask-field disclosure card. Body fills remaining left-pane height and scrolls
/// inside the card. Other long fields keep More/Less.
private struct ConditionalAskFieldPreviewCard: View {
    let line: ConditionalFieldPreviewLine
    var fillsAvailableHeight: Bool = false
    @State private var expanded = false

    private var isLong: Bool { line.value.count > 120 || line.value.contains("\n") }
    private var isAddressField: Bool {
        ["From", "To", "Cc"].contains(line.label)
    }

    var body: some View {
        ConditionalAskCard(fillsHeight: fillsAvailableHeight) {
            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .firstTextBaseline) {
                    Text(line.label)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Spacer(minLength: 8)
                    if !fillsAvailableHeight, isLong {
                        Button(expanded ? "Less" : "More") {
                            withAnimation(.easeInOut(duration: 0.15)) {
                                expanded.toggle()
                            }
                        }
                        .buttonStyle(.plain)
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(Color.accentColor)
                    }
                }

                if isAddressField {
                    addressPreview
                } else if fillsAvailableHeight {
                    ScrollView {
                        Text(line.value)
                            .font(.caption)
                            .foregroundStyle(.primary)
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    .clipped()
                } else if isLong {
                    ScrollView {
                        Text(line.value)
                            .font(.caption)
                            .foregroundStyle(.primary)
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .frame(
                        maxWidth: .infinity,
                        maxHeight: expanded
                            ? ConditionalAskLayout.fieldPreviewExpandedHeight
                            : ConditionalAskLayout.fieldPreviewCollapsedHeight,
                        alignment: .topLeading
                    )
                    .clipped()
                } else {
                    // Short fields (e.g. empty attachment names) hug content height.
                    Text(line.value)
                        .font(.caption)
                        .foregroundStyle(.primary)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .frame(
                maxWidth: .infinity,
                maxHeight: fillsAvailableHeight ? .infinity : nil,
                alignment: .topLeading
            )
        }
    }

    @ViewBuilder
    private var addressPreview: some View {
        let trimmed = line.value.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty || trimmed == "(empty)" || trimmed == "—" {
            Text(trimmed.isEmpty ? "—" : trimmed)
                .font(.caption)
                .foregroundStyle(.secondary)
                .italic()
        } else {
            let addresses = MailAddressParts.parseList(trimmed)
            if addresses.isEmpty {
                Text(trimmed)
                    .font(.caption)
                    .textSelection(.enabled)
            } else {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(Array(addresses.enumerated()), id: \.offset) { _, parts in
                        HStack(spacing: 6) {
                            if let name = parts.name {
                                Text(name)
                                    .font(.caption)
                                    .textSelection(.enabled)
                            }
                            if let email = parts.email {
                                AddressBadge(email: email)
                            }
                        }
                    }
                }
            }
        }
    }
}

private struct FlowFieldChips: View {
    let labels: [String]

    var body: some View {
        HStack(spacing: 4) {
            ForEach(labels, id: \.self) { label in
                Text(label)
                    .font(.caption2.weight(.semibold))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(
                        RoundedRectangle(cornerRadius: 4, style: .continuous)
                            .fill(Color.orange.opacity(0.18))
                    )
                    .foregroundStyle(.orange)
            }
        }
    }
}

#if DEBUG
private enum ConditionalAccessPreviewSamples {
    static let htmlBody = """
    <html><head><style>body {margin:0;padding:0; background:#f3f3f3;}</style></head>
    <body style="font-family:-apple-system;padding:12px;">
    <p>Hi there,&zwnj;&zwnj;&zwnj;</p>
    <p>Your <strong>Tapo</strong> order is ready. Tracking:
    <a href="https://example.com/track">ABC-123</a></p>
    <ul><li>Item A</li><li>Item B</li></ul>
    <p style="color:#666;">— MailGent preview sample</p>
    </body></html>
    """

    static let plainBody = """
    Hi there,\u{200C}\u{200C}\u{200C}
    Your Tapo order is ready. Tracking: ABC-123
    - Item A
    - Item B
    — MailGent preview sample
    """

    static var context: ConditionalAccessPromptContext {
        ConditionalAccessPromptContext(
            agentName: "Cursor",
            accountID: "19DAAEEB-B0A9-4C37-820B-A55EC8B979CB",
            placement: "INBOX",
            messageID: "42",
            internetMessageID: "<sample@mailgent.local>",
            requestedFields: ["Body", "Attachment names", "Attachment content"],
            fieldPreviews: [
                ConditionalFieldPreviewLine(
                    label: "Body",
                    value: MailMIME.plainText(fromHTML: htmlBody)
                ),
                ConditionalFieldPreviewLine(label: "Attachment names", value: "(empty)"),
                ConditionalFieldPreviewLine(label: "Attachment content", value: "(empty)"),
            ],
            htmlBody: htmlBody,
            envelope: ConditionalMessageEnvelope(
                subject: "Your Tapo order is ready",
                from: "Tapo Orders <orders@tapo.example>",
                to: "<you@icloud.com>",
                cc: "",
                date: "2026-10-07 16:12"
            )
        )
    }

    static var request: ConditionalAccessPromptRequest {
        ConditionalAccessPromptRequest(context: context)
    }
}

#Preview("Ask dialog") {
    ConditionalAccessPromptDialog(
        request: ConditionalAccessPreviewSamples.request,
        accountLabel: "19DAAEEB-B0A9-4C37-820B-A55EC8B979CB",
        onAllow: {},
        onBlock: {},
        showOpenInMail: true,
        onOpenInMail: {}
    )
    .background(Color(nsColor: .windowBackgroundColor))
}

#Preview("Ask compact") {
    ConditionalAccessPromptDialog(
        request: ConditionalAccessPreviewSamples.request,
        accountLabel: "19DAAEEB-B0A9-4C37-820B-A55EC8B979CB",
        onAllow: {},
        onBlock: {},
        showOpenInMail: true,
        onOpenInMail: {},
        showsMessagePreview: false
    )
    .background(Color(nsColor: .windowBackgroundColor))
}
#endif
