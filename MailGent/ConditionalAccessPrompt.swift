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
/// Each request is its own `DetachedWindowHost` window. Pending rows live on
/// `AskQueueIndicator`, not a single coordinator request.
@MainActor
public final class ConditionalAccessPromptCoordinator: ObservableObject {
    public init() {}

    /// Request a decision from the user. Suspends until Allow / Block / rematch recheck for this request.
    /// Concurrent gets each open their own dialog; one decision never resolves another.
    /// Always returns (never throws); Block is fail-closed (user Block / traffic-light close).
    public func requestDecision(
        context: ConditionalAccessPromptContext,
        accountLabel: String? = nil,
        ruleSupport: ConditionalAccessAskRuleSupport? = nil
    ) async -> ConditionalAccessPromptOutcome {
        let request = ConditionalAccessPromptRequest(context: context)
        let mailboxLabel = accountLabel.flatMap { $0.isEmpty ? nil : $0 } ?? context.accountID
        let fieldsText = context.requestedFields.joined(separator: ", ")

        let outcome = await DetachedWindowHost.shared.runConditionalAsk(
            request: request,
            accountLabel: mailboxLabel,
            ruleSupport: ruleSupport
        )

        let label: String
        switch outcome {
        case .allow: label = "allow"
        case .block: label = "block"
        case .recheck: label = "recheck"
        }
        MailGentLog.trace(
            "conditional access \(label) agent=\(context.agentName) fields=\(fieldsText)"
        )
        return outcome
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
    /// Soft ceiling for the Ask popup — left column scrolls instead of growing toward full-screen.
    static let dialogMaxHeight: CGFloat = 560
    /// Non-body long-field collapsed / expanded preview heights.
    static let fieldPreviewCollapsedHeight: CGFloat = 64
    static let fieldPreviewExpandedHeight: CGFloat = 200
    /// Body card text area cap inside the scrolling left column (keep compact; full body is on the right).
    static let bodyPreviewMaxHeight: CGFloat = 120
    /// Block / Allow row.
    static let footerBlockHeight: CGFloat = 28
    /// Breathing room between left cards and the HSplitView divider.
    static let splitTrailingGap: CGFloat = 10

    static var compactWidth: CGFloat { leftColumnWidth + pad * 2 }
    static var expandedWidth: CGFloat {
        leftColumnWidth + gap + previewColumnWidth + pad * 2
    }

    static func contentSize(previewVisible: Bool, preferredHeight: CGFloat? = nil) -> NSSize {
        let height = clampedHeight(preferredHeight ?? dialogHeight)
        return NSSize(
            width: previewVisible ? expandedWidth : compactWidth,
            height: height
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

    /// Collapsed centered access-lead row (icon + one-liner + More).
    /// Vertical clearance matches chrome `pad` above and VStack `gap` below (both 12).
    static let whyHelpCollapsedHeight: CGFloat = 24

    /// Window height from measured left scroll-content + why-help chrome, capped for a popup.
    static func windowHeight(
        forLeftScrollContent contentHeight: CGFloat,
        whyHelpHeight: CGFloat = whyHelpCollapsedHeight
    ) -> CGFloat {
        let chrome =
            pad * 2
            + whyHelpHeight
            + gap
            + contentHeight
            + gap
            + footerBlockHeight
        return clampedHeight(chrome)
    }

    static func clampedHeight(_ height: CGFloat) -> CGFloat {
        let screenCap: CGFloat = {
            guard let screen = NSScreen.main else { return dialogMaxHeight }
            // Leave menu-bar / Dock breathing room; never taller than dialogMaxHeight.
            let visibleCap = max(dialogMinHeight, screen.visibleFrame.height * 0.72)
            return min(dialogMaxHeight, visibleCap)
        }()
        return min(max(height, dialogMinHeight), screenCap)
    }
}

/// Reports the intrinsic height of the Ask left-column scroll content.
private struct AskLeftScrollContentHeightKey: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

/// Reports the height of the collapsible Ask access-lead help row.
private struct AskWhyHelpHeightKey: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

/// In-app Preview content — Companion `MessageBodyView` (HTML via WKWebView).
/// Entire message only (not Ask-field chips); fills the right-hand pane.
struct ConditionalAccessInAppPreview: View {
    let context: ConditionalAccessPromptContext

    /// Default denser than Companion Read so more of the thread fits the Ask canvas.
    private static let defaultZoom: CGFloat = 0.75
    private static let zoomStep: CGFloat = 0.25
    private static let minZoom: CGFloat = 0.5
    private static let maxZoom: CGFloat = 1.5

    @State private var pageZoom: CGFloat = Self.defaultZoom
    @State private var hoveringCanvas = false

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
        // Floating sticky −|+ over the canvas (top-trailing). Hover via AppKit tracker
        // because WKWebView / NSScrollView eat SwiftUI onHover.
        ZStack(alignment: .topTrailing) {
            Group {
                if hasHTML || context.fieldPreviews.contains(where: { $0.label == "Body" }) {
                    MessageBodyView(
                        // Empty plain when HTML exists so MessageBodyView does not discard HTML
                        // via the closed-prefix heuristic against Ask field text.
                        readBody: hasHTML ? .text("") : plainFallback,
                        htmlBody: context.htmlBody,
                        pageZoom: pageZoom,
                        ensureReadableInsets: true
                    )
                } else {
                    Text("(no message body to preview)")
                        .foregroundStyle(.secondary)
                        .italic()
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                }
            }
            .id("ask-preview-\(context.messageID)")
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .clipped()

            AskPreviewHoverTracker(isHovering: $hoveringCanvas)
                .allowsHitTesting(false)

            AskPreviewZoomControls(
                zoom: pageZoom,
                canZoomOut: pageZoom > Self.minZoom + 0.001,
                canZoomIn: pageZoom < Self.maxZoom - 0.001,
                onZoomOut: {
                    pageZoom = max(Self.minZoom, pageZoom - Self.zoomStep)
                },
                onZoomIn: {
                    pageZoom = min(Self.maxZoom, pageZoom + Self.zoomStep)
                }
            )
            .padding(.top, 8)
            .padding(.trailing, 10)
            .opacity(hoveringCanvas ? 1 : 0)
            .allowsHitTesting(hoveringCanvas)
            .accessibilityHidden(!hoveringCanvas)
            .onHover { hovering in
                if hovering { hoveringCanvas = true }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Message preview")
        .accessibilityValue("\(Int((pageZoom * 100).rounded())) percent")
    }
}

/// Pass-through hover probe: tracking area fires over WKWebView / NSScrollView without stealing clicks/scroll.
private struct AskPreviewHoverTracker: NSViewRepresentable {
    @Binding var isHovering: Bool

    func makeNSView(context: Context) -> AskPreviewHoverNSView {
        let view = AskPreviewHoverNSView()
        view.onHoverChange = { hovering in
            DispatchQueue.main.async {
                withAnimation(.easeInOut(duration: 0.15)) {
                    isHovering = hovering
                }
            }
        }
        return view
    }

    func updateNSView(_ nsView: AskPreviewHoverNSView, context: Context) {
        nsView.onHoverChange = { hovering in
            DispatchQueue.main.async {
                withAnimation(.easeInOut(duration: 0.15)) {
                    isHovering = hovering
                }
            }
        }
    }
}

private final class AskPreviewHoverNSView: NSView {
    var onHoverChange: ((Bool) -> Void)?
    private var tracking: NSTrackingArea?

    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let tracking {
            removeTrackingArea(tracking)
        }
        let area = NSTrackingArea(
            rect: .zero,
            options: [.activeInKeyWindow, .mouseEnteredAndExited, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(area)
        tracking = area
    }

    override func mouseEntered(with event: NSEvent) {
        onHoverChange?(true)
    }

    override func mouseExited(with event: NSEvent) {
        onHoverChange?(false)
    }
}

/// Compact floating − | + for Ask preview; sticky top-trailing while the canvas is hovered.
private struct AskPreviewZoomControls: View {
    let zoom: CGFloat
    let canZoomOut: Bool
    let canZoomIn: Bool
    let onZoomOut: () -> Void
    let onZoomIn: () -> Void

    var body: some View {
        HStack(spacing: 0) {
            zoomButton(systemImage: "minus", enabled: canZoomOut, action: onZoomOut)
                .help("Zoom out")
                .accessibilityLabel("Zoom out")

            Rectangle()
                .fill(Color.secondary.opacity(0.28))
                .frame(width: 1, height: 14)

            zoomButton(systemImage: "plus", enabled: canZoomIn, action: onZoomIn)
                .help("Zoom in")
                .accessibilityLabel("Zoom in")
        }
        .frame(height: SecondaryActionMetrics.controlHeight)
        .padding(1)
        .background {
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(.regularMaterial)
                .overlay {
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .strokeBorder(Color.secondary.opacity(0.32), lineWidth: 1)
                }
                .shadow(color: Color.black.opacity(0.10), radius: 1, y: 0.5)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Preview zoom")
        .accessibilityValue("\(Int((zoom * 100).rounded())) percent")
    }

    private func zoomButton(
        systemImage: String,
        enabled: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 11, weight: .semibold))
                .frame(width: 26, height: SecondaryActionMetrics.controlHeight - 2)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .opacity(enabled ? 1 : 0.35)
        .foregroundStyle(.primary)
    }
}

/// SwiftUI view for the conditional access prompt dialog (previews / optional hosts).
struct ConditionalAccessPromptDialog: View {
    let request: ConditionalAccessPromptRequest
    let accountLabel: String
    let onAllow: () -> Void
    let onBlock: () -> Void
    var ruleSupport: ConditionalAccessAskRuleSupport? = nil
    var showOpenInMail: Bool = false
    var onOpenInMail: (() -> Void)? = nil
    /// Outer inset; off when a parent owns the padding.
    var chromePadding: Bool = true
    /// When false, hide the right-hand rendered message pane (Xcode canvas left-only).
    var showsMessagePreview: Bool = true
    /// Host resizes the Ask window when Preview toggles.
    var onPreviewVisibilityChange: ((Bool) -> Void)? = nil
    /// Host fits window height to the left column when content is measured.
    var onPreferredHeightChange: ((CGFloat) -> Void)? = nil

    @State private var messagePreviewVisible: Bool = true
    @State private var hoveringIdentity = false
    @State private var leftScrollReset = 0
    @State private var whyThisWindowExpanded = false
    @State private var leftScrollContentHeight: CGFloat = 0
    @State private var whyHelpHeight: CGFloat = ConditionalAskLayout.whyHelpCollapsedHeight
    @StateObject private var ruleDraft = ConditionalAccessAskRuleDraft()

    private var envelope: ConditionalMessageEnvelope { request.context.envelope }
    private var rightShowsRuleEditor: Bool {
        ruleSupport != nil && ruleDraft.detailOpen && ruleDraft.isArmed
    }

    private var requestedFieldsSummary: String {
        let labels = request.requestedFields
        guard !labels.isEmpty else { return "one or more fields" }
        if labels.count == 1 { return labels[0] }
        if labels.count == 2 { return "\(labels[0]) and \(labels[1])" }
        return labels.dropLast().joined(separator: ", ") + ", and \(labels.last!)"
    }

    private var accessHelpDetail: String {
        "This grant sets \(requestedFieldsSummary) to Ask. Allow shares those fields for this read only; Block keeps them withheld."
    }

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
            leftScrollReset &+= 1
            if let ruleSupport {
                ruleDraft.reset(for: request.context, support: ruleSupport)
            }
        }
        .onChange(of: request.id) { _, _ in
            leftScrollReset &+= 1
            if let ruleSupport {
                ruleDraft.reset(for: request.context, support: ruleSupport)
            }
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
            whyThisWindowHelp

            // Scroll the whole card stack. Attachment fields sit above Body so a long
            // body never buries them; Body itself is hard-capped (see maxTextHeight).
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: ConditionalAskLayout.gap) {
                        Color.clear.frame(height: 0).id("ask-left-top")

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
                            }
                            // Attachments / other post-body fields first — always above the fold.
                            ForEach(postBodyFieldPreviews, id: \.label) { line in
                                ConditionalAskFieldPreviewCard(line: line)
                            }
                            if let bodyFieldPreview {
                                ConditionalAskFieldPreviewCard(
                                    line: bodyFieldPreview,
                                    maxTextHeight: ConditionalAskLayout.bodyPreviewMaxHeight
                                )
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                    .background(
                        GeometryReader { geo in
                            Color.clear.preference(
                                key: AskLeftScrollContentHeightKey.self,
                                value: geo.size.height
                            )
                        }
                    )
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .onPreferenceChange(AskLeftScrollContentHeightKey.self) { height in
                    guard height > 0 else { return }
                    leftScrollContentHeight = height
                    reportPreferredHeight()
                    // Window height changes can leave the stack mid-scroll — re-pin to top.
                    DispatchQueue.main.async {
                        proxy.scrollTo("ask-left-top", anchor: .top)
                    }
                }
                .onChange(of: leftScrollReset) { _, _ in
                    DispatchQueue.main.async {
                        proxy.scrollTo("ask-left-top", anchor: .top)
                    }
                }
                .onAppear {
                    DispatchQueue.main.async {
                        proxy.scrollTo("ask-left-top", anchor: .top)
                    }
                }
            }

            askFooter
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .onPreferenceChange(AskWhyHelpHeightKey.self) { height in
            guard height > 0 else { return }
            whyHelpHeight = height
            reportPreferredHeight()
        }
        .onChange(of: request.id) { _, _ in
            whyThisWindowExpanded = false
        }
    }

    private var whyThisWindowHelp: some View {
        Button {
            withAnimation(.easeInOut(duration: 0.18)) {
                whyThisWindowExpanded.toggle()
            }
        } label: {
            VStack(alignment: .center, spacing: 6) {
                HStack(alignment: .center, spacing: 8) {
                    Image(systemName: "questionmark.circle.fill")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(.orange)
                    Text("\(request.agentName) wants access to the email below")
                        .font(.callout.weight(.medium))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                    Text(whyThisWindowExpanded ? "Less" : "More")
                        .font(.callout.weight(.semibold))
                        .foregroundStyle(.orange)
                        .fixedSize()
                }
                if whyThisWindowExpanded {
                    Text(accessHelpDetail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: .infinity)
                }
            }
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
            .background(
                GeometryReader { geo in
                    Color.clear.preference(
                        key: AskWhyHelpHeightKey.self,
                        value: geo.size.height
                    )
                }
            )
        }
        .buttonStyle(.plain)
        .accessibilityHint(
            whyThisWindowExpanded
                ? "Hide access details"
                : "Show which fields are requested and what Allow or Block does"
        )
    }

    private func reportPreferredHeight() {
        guard leftScrollContentHeight > 0 else { return }
        onPreferredHeightChange?(
            ConditionalAskLayout.windowHeight(
                forLeftScrollContent: leftScrollContentHeight,
                whyHelpHeight: max(whyHelpHeight, ConditionalAskLayout.whyHelpCollapsedHeight)
            )
        )
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

                envelopeRow(label: "Subject", value: envelope.subject, pick: ruleSupport != nil ? .subject : nil)
                envelopeAddressRow(label: "From", raw: envelope.from, pick: ruleSupport != nil ? .from : nil)
                if !envelope.to.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    envelopeAddressRow(label: "To", raw: envelope.to, pick: nil, showPickSlot: ruleSupport != nil)
                }
                if !envelope.cc.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    envelopeAddressRow(label: "Cc", raw: envelope.cc, pick: nil, showPickSlot: ruleSupport != nil)
                }
                envelopeRow(label: "Date", value: envelope.date, pick: nil, showPickSlot: ruleSupport != nil)

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
        Group {
            if rightShowsRuleEditor, let ruleSupport {
                ConditionalAccessAskRulePanel(
                    context: request.context,
                    support: ruleSupport,
                    draft: ruleDraft,
                    onClose: {
                        withAnimation(SecondaryActionMetrics.expandAnimation) {
                            ruleDraft.setDetailOpen(false, context: request.context)
                        }
                    }
                )
            } else {
                ConditionalAccessInAppPreview(context: request.context)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var askFooter: some View {
        HStack(spacing: 8) {
            Button("Block") {
                resolveDecision(.block)
            }
            .buttonStyle(AskPrimaryFooterButtonStyle(prominent: false))
            .keyboardShortcut(.cancelAction)

            Button("Allow") {
                resolveDecision(.allow)
            }
            .buttonStyle(AskPrimaryFooterButtonStyle(prominent: true))
            .keyboardShortcut(.defaultAction)

            if ruleSupport != nil, ruleDraft.isArmed {
                Text(ruleDraft.fateLabel)
                    .font(.system(size: 12, weight: .regular))
                    .foregroundStyle(.primary)
                    .fixedSize()
            }

            Spacer(minLength: 8)

            if ruleSupport != nil, ruleDraft.isArmed {
                Button(ruleDraft.detailOpen ? "Close rule edit" : "Edit rule ›") {
                    withAnimation(SecondaryActionMetrics.expandAnimation) {
                        if !ruleDraft.detailOpen {
                            ensurePreviewColumnVisible()
                        }
                        ruleDraft.setDetailOpen(!ruleDraft.detailOpen, context: request.context)
                    }
                }
                .buttonStyle(AskPrimaryFooterButtonStyle(prominent: false))
            }
        }
    }

    private func resolveDecision(_ decision: ConditionalAccessDecision) {
        if let ruleSupport, ruleDraft.isArmed,
           let saved = ruleDraft.commit(
               decision: decision,
               context: request.context,
               support: ruleSupport
           )
        {
            DetachedWindowHost.shared.rematchPendingAsks(
                excluding: request.id,
                agentID: request.context.agentID,
                rule: saved,
                enablements: ruleSupport.allEnablements()
            )
        }
        switch decision {
        case .allow: onAllow()
        case .block: onBlock()
        }
    }

    private func togglePreview() {
        if rightShowsRuleEditor {
            withAnimation(SecondaryActionMetrics.expandAnimation) {
                ruleDraft.setDetailOpen(false, context: request.context)
            }
            return
        }
        let next = !messagePreviewVisible
        withAnimation(SecondaryActionMetrics.expandAnimation) {
            messagePreviewVisible = next
        }
        onPreviewVisibilityChange?(next)
    }

    private func ensurePreviewColumnVisible() {
        guard showsMessagePreview, !messagePreviewVisible else { return }
        messagePreviewVisible = true
        onPreviewVisibilityChange?(true)
    }

    private static let envelopeLabelWidth: CGFloat = 52

    private func envelopeLabel(_ label: String) -> some View {
        Text(label)
            .font(.caption2)
            .foregroundStyle(.secondary)
            .frame(width: Self.envelopeLabelWidth, alignment: .leading)
            .textSelection(.enabled)
    }

    private func envelopeRow(
        label: String,
        value: String,
        pick: AskEnvelopePick? = nil,
        showPickSlot: Bool = false
    ) -> some View {
        HStack(alignment: .center, spacing: 8) {
            envelopeLabel(label)
            Text(value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "—" : value)
                .font(.caption2)
                .textSelection(.enabled)
                .lineLimit(3)
                .frame(maxWidth: .infinity, alignment: .leading)
            envelopePickControl(pick: pick, showSlot: showPickSlot || pick != nil)
        }
    }

    private func envelopeAddressRow(
        label: String,
        raw: String,
        pick: AskEnvelopePick? = nil,
        showPickSlot: Bool = false
    ) -> some View {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        let addresses = MailAddressParts.parseList(trimmed)
        // Top-align so the + stays on the first line when name/email stacks.
        return HStack(alignment: .top, spacing: 8) {
            envelopeLabel(label)
            Group {
                if trimmed.isEmpty {
                    Text("—")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                } else if addresses.isEmpty {
                    Text(trimmed)
                        .font(.caption2)
                        .textSelection(.enabled)
                        .lineLimit(3)
                } else {
                    FlowAddressBadges(addresses: addresses)
                        .font(.caption2)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            envelopePickControl(pick: pick, showSlot: showPickSlot || pick != nil)
        }
    }

    @ViewBuilder
    private func envelopePickControl(pick: AskEnvelopePick?, showSlot: Bool) -> some View {
        if !showSlot {
            EmptyView()
        } else if let pick, let ruleSupport {
            let on = ruleDraft.picked.contains(pick)
            SecondaryActionButton(
                title: on ? "In rule" : "Add to rule",
                systemImage: on ? "checkmark" : "plus",
                isOn: on,
                expandLeadingOverlay: true
            ) {
                withAnimation(SecondaryActionMetrics.expandAnimation) {
                    ensurePreviewColumnVisible()
                    ruleDraft.togglePick(pick, context: request.context, support: ruleSupport)
                }
            }
        } else {
            Color.clear
                .frame(
                    width: SecondaryActionMetrics.controlHeight,
                    height: SecondaryActionMetrics.controlHeight
                )
                .accessibilityHidden(true)
        }
    }
}

/// Compact Block / Allow chrome toward proto padding (5×8). Shared by Ask + propose-send.
struct AskPrimaryFooterButtonStyle: ButtonStyle {
    var prominent: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: prominent ? .semibold : .medium))
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .foregroundStyle(prominent ? Color.white : Color.primary)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(prominent ? Color.accentColor : Color(nsColor: .controlBackgroundColor))
            )
            .overlay {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .strokeBorder(
                        prominent ? Color.accentColor : Color.secondary.opacity(0.32),
                        lineWidth: 1
                    )
            }
            .opacity(configuration.isPressed ? 0.9 : 1)
    }
}

/// Name + grey email badge side-by-side when they fit; otherwise name on line 1, email on line 2.
/// Callers set `.font(...)` (envelope uses caption2; field cards use caption).
struct FlowAddressBadges: View {
    let addresses: [MailAddressParts]

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(Array(addresses.enumerated()), id: \.offset) { _, parts in
                addressBlock(parts)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private func addressBlock(_ parts: MailAddressParts) -> some View {
        switch (parts.name, parts.email) {
        case let (name?, email?):
            // Horizontal candidate must refuse to wrap so ViewThatFits can fall back.
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(name)
                        .textSelection(.enabled)
                        .lineLimit(1)
                        .fixedSize(horizontal: true, vertical: false)
                    AddressBadge(email: email, lineLimit: 1)
                        .fixedSize(horizontal: true, vertical: false)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(name)
                        .textSelection(.enabled)
                    AddressBadge(email: email)
                }
            }
        case let (name?, nil):
            Text(name)
                .textSelection(.enabled)
        case let (nil, email?):
            AddressBadge(email: email)
        case (nil, nil):
            EmptyView()
        }
    }
}

struct ConditionalAskCard<Content: View>: View {
    var compact: Bool = false
    @ViewBuilder let content: Content

    var body: some View {
        content
            .padding(
                compact
                    ? EdgeInsets(top: 6, leading: 10, bottom: 6, trailing: 10)
                    : EdgeInsets(
                        top: ConditionalAskLayout.pad,
                        leading: ConditionalAskLayout.pad,
                        bottom: ConditionalAskLayout.pad,
                        trailing: ConditionalAskLayout.pad
                    )
            )
            .frame(maxWidth: .infinity, alignment: .topLeading)
            .background(
                RoundedRectangle(cornerRadius: ConditionalAskLayout.cardRadius, style: .continuous)
                    .fill(Color.secondary.opacity(0.06))
            )
            .clipShape(
                RoundedRectangle(cornerRadius: ConditionalAskLayout.cardRadius, style: .continuous)
            )
    }
}

/// One Ask-field disclosure card. Empty attachment fields stay one-line compact;
/// Body uses a capped scroll area; other long fields keep More/Less.
private struct ConditionalAskFieldPreviewCard: View {
    let line: ConditionalFieldPreviewLine
    /// When set (Body), text scrolls inside this height instead of stretching the pane.
    var maxTextHeight: CGFloat? = nil
    @State private var expanded = false

    private var trimmedValue: String {
        line.value.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var isEmptyValue: Bool {
        trimmedValue.isEmpty
            || trimmedValue == "(empty)"
            || trimmedValue == "—"
    }

    private var isLong: Bool { line.value.count > 120 || line.value.contains("\n") }
    private var isAddressField: Bool {
        ["From", "To", "Cc"].contains(line.label)
    }

    @ViewBuilder
    private var titleLabel: some View {
        HStack(alignment: .center, spacing: 6) {
            Text(line.label)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            if let badge = line.badge, !badge.isEmpty {
                Text(badge)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.orange)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(
                        Capsule(style: .continuous)
                            .strokeBorder(Color.orange.opacity(0.55), lineWidth: 1)
                    )
            }
        }
    }

    var body: some View {
        if isEmptyValue, !isAddressField {
            ConditionalAskCard(compact: true) {
                HStack(alignment: .center, spacing: 8) {
                    titleLabel
                    Spacer(minLength: 8)
                    Text(trimmedValue.isEmpty ? "(empty)" : trimmedValue)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .italic()
                }
            }
        } else {
            ConditionalAskCard {
                VStack(alignment: .leading, spacing: 6) {
                    HStack(alignment: .center) {
                        titleLabel
                        Spacer(minLength: 8)
                        if maxTextHeight == nil, isLong {
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
                    } else if let maxTextHeight {
                        // Fixed height (not maxHeight): nested ScrollView + fixedSize parents
                        // otherwise report full text height and bury everything below Body.
                        ScrollView {
                            Text(line.value)
                                .font(.caption)
                                .foregroundStyle(.primary)
                                .textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .frame(height: maxTextHeight, alignment: .topLeading)
                        .frame(maxWidth: .infinity, alignment: .topLeading)
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
                        Text(line.value)
                            .font(.caption)
                            .foregroundStyle(.primary)
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .topLeading)
            }
        }
    }

    @ViewBuilder
    private var addressPreview: some View {
        if isEmptyValue {
            Text(trimmedValue.isEmpty ? "—" : trimmedValue)
                .font(.caption)
                .foregroundStyle(.secondary)
                .italic()
        } else {
            let addresses = MailAddressParts.parseList(trimmedValue)
            if addresses.isEmpty {
                Text(trimmedValue)
                    .font(.caption)
                    .textSelection(.enabled)
            } else {
                FlowAddressBadges(addresses: addresses)
                    .font(.caption)
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
/// Sample Ask payloads for Xcode canvas + menu-bar “Debug: Ask layout…”.
enum AskLayoutSandboxSamples {
    static let htmlBody = """
    <html><head><style>body {margin:0;padding:0; background:#f3f3f3;}</style></head>
    <body style="font-family:-apple-system;padding:12px;">
    <p>Hi Marek,</p>
    <p>I wanted to follow up on the <strong>Automation Engineer, AMZL</strong> role.</p>
    <p>Your <strong>Tapo</strong> order is ready. Tracking:
    <a href="https://example.com/track">ABC-123</a></p>
    <ul><li>Item A</li><li>Item B</li><li>Item C — longer line for scroll testing</li></ul>
    <p style="color:#666;">— MailGent preview sample</p>
    </body></html>
    """

    /// Real Indeed job-match plain body (long + many URLs) for scroll / zoom stress testing.
    static let longPlainBody = """
    Hi Marek,

    Your background in IoT and EV charging systems could align with this Senior Embedded Software Engineer role at Bramah Safeguarding CIC. If you're seeking a position with 60% new development and a hybrid work model, feel free to apply now or review the job description to learn more.

    Senior Embedded Software Engineer
    Bramah Safeguarding CIC
    Birmingham B1
    Salary: £70,000 - £90,000 a year
    Job type: Permanent, Full-time
    Work setting: Hybrid work, In-person

    Benefits:
      - Company pension
      - Work from home
      - Cycle to work scheme
      - Life insurance

    View job: https://cts.indeed.com/v3/H4sIAAAAAAAA_42RW4-aQBSA_wtJfSorM8jNhDSKVS6Slcpa7YsZhgGGuzAji5v978umaR_61KeTfF9OTnK-N4ELSyFjrO2X8zkvnmgdExI_4aaad3iOy-JbXpiSJicIKgRijKSFDGZJ11Rm3kQUous0KsRwJnYEYUbviNGmFkkt7tZXUiFazlhhgmKR5FACUZnCVJfALIrM80srevnt-Vittp7l8Z_fJfl2DJQEtiJX1_CiOboduPLRcB81GoPF3gnD7ITknXS7PoMLjQ22vYyV3z9slbzQric04xk5yxt-qenml69Gg5K4AWz6YbS2K7_XO1vZ0NraeuC0J_dRR8Z2VPt45brlWQVJEY4ucNbBLTzoJ-QOnmshGomYnn6wFO8aVg6-3Qfavt2dhmqtY5RTWHvOF3kzey1wZB4bK1E1H8YHbhvi6y1wpXX0KGIrPhxmXd7-eQXgLasUSnQJCl-FSli-CQjjhtfMiacgwJCBqhlAlpRJozR1m-i3kKCuA9lQF9okcElxEWZdw9Nskqzj5C8dWzKhOyXDFGiin8km8L_Rpg1WfB78J5zw_v4B6swDyzQCAAA/x6abD8z7bhgVPpwRn-kIJ5Jot2N8LItxSHPB8xg8Yoo
    Apply now: https://cts.indeed.com/v3/H4sIAAAAAAAA_42RW4-aQBSA_wtJfSorM8jNhDSKVS6Slcpa7YsZhgGGuzAji5v978umaR_61KeTfF9OTnK-N4ELSyFjrO2X8zkvnmgdExI_4aaad3iOy-JbXpiSJicIKgRijKSFDGZJ11Rm3kQUous0KsRwJnYEYUbviNGmFkkt7tZXUiFazlhhgmKR5FACUZnCVJfALIrM80srevnt-Vittp7l8Z_fJfl2DJQEtiJX1_CiOboduPLRcB81GoPF3gnD7ITknXS7PoMLjQ22vYyV3z9slbzQric04xk5yxt-qenml69Gg5K4AWz6YbS2K7_XO1vZ0NraeuC0J_dRR8Z2VPt45brlWQVJEY4ucNbBLTzoJ-QOnmshGomYnn6wFO8aVg6-3Qfavt2dhmqtY5RTWHvOF3kzey1wZB4bK1E1H8YHbhvi6y1wpXX0KGIrPhxmXd7-eQXgLasUSnQJCl-FSli-CQjjhtfMiacgwJCBqhlAlpRJozR1m-i3kKCuA9lQF9okcElxEWZdw9Nskqzj5C8dWzKhOyXDFGiin8km8L_Rpg1WfB78J5zw_v4B6swDyzQCAAA/x6abD8z7bhgVPpwRn-kIJ5Jot2N8LItxSHPB8xg8Yoo

    Do you want to get more jobs like this?
    No: https://cts.indeed.com/v3/H4sIAAAAAAAA_12Q226CQBRF_4WkfeooI8rFxDQaiMEbeAstL2SAUQaYAWG4FOO_F9Okabrfzl45-2HdhUqYChHneTkdDiniQTQgLMQ4HAQZHRJWE444yVj5A0HRX-w6hO88mcFkfIlHIvTT6-iqivCVsEs2mz9ztj7abXei6qJVWa37zgQ1N2JuR769oHZnnsmuMBKPr8TtWY2lzVrR3MVtLBsxtSfKoZWQbtonZQnkI9B43M7DTjt0HYWf-265kY471QjFfFmuPVzcygppKVKow_MCHwF2Y1gQGKiNo8qxZQFvPk4hWjWlb-Cq2u0z13ctMG91JgPgMWTYjQrs3MHWok6aSE_HDc7YyjFryTq_SPrrpcjojIwQwBSRFFx6PT4KEuFNoML0LqAgyCrGzbBXCTUJyooGJXHS4yAlQXKKiqy6Rj3kRYV_268c99WfLZ48__85FR6Pb5SRd1-kAQAA/hWJsQlvQXlK_4jxF2Q_CPkdwnjtgRm5z6b6FTGmBzJc
    Maybe: https://cts.indeed.com/v3/H4sIAAAAAAAA_12Q226CQBRF_4WkfeooI8rFxDQaiMEbeAstL2SAUQaYAWG4FOO_F9Okabrfzl45-2HdhUqYChHneTkdDiniQTQgLMQ4HAQZHRJWE444yVj5A0HRX-w6lN55MoPJ-BKPROin19FVFeErYZdsNn_mbH202-5E1UWrslr3nQlqbsTcjnx7Qe3OPJNdYSQeX4nbsxpLm7WiuYvbWDZiak-UQysh3bRPyhLIR6DxuJ2HnXboOgo_991yIx13qhGK-bJce7i4lRXSUqRQh-cFPgLsxrAgMFAbR5VjywLefJxCtGpK38BVtdtnru9aYN7qTAbAY8iwGxXYuYOtRZ00kZ6OG5yxlWPWknV-kfTXS5HRGRkhgCkiKbj0enwUJMKbQIXpXUBBkFWMm2GvEmoSlBUNSuKkx0FKguQUFVl1jXrIiwr_tl857qs_Wzx5_v9zKjwe3z5lt_qkAQAA/3n-Ka9VJMd74hkXMzTmOxdi10EQCkO-kMUonBWAiUcs
    Yes: https://cts.indeed.com/v3/H4sIAAAAAAAA_12Q226CQBRF_4WkfeooI8rFxDQaiMEbeAstL2SAUQaYAWG4FOO_F9Okabrfzl45-2HdhUqYChHneTkdDiniQTQgLMQ4HAQZHRJWE444yVj5A0HRX-w6nLzzZAaT8SUeidBPr6OrKsJXwi7ZbP7M2fpot92JqotWZbXuOxPU3Ii5Hfn2gtqdeSa7wkg8vhK3ZzWWNmtFcxe3sWzE1J4oh1ZCummflCWQj0DjcTsPO-3QdRR-7rvlRjruVCMU82W59nBxKyukpUihDs8LfATYjWFBYKA2jirHlgW8-TiFaNWUvoGrarfPXN-1wLzVmQyAx5BhNyqwcwdbizppIj0dNzhjK8esJev8IumvlyKjMzJCAFNEUnDp9fgoSIQ3gQrTu4CCIKsYN8NeJdQkKCsalMRJj4OUBMkpKrLqGvWQFxX-bb9y3Fd_tnjy_P_nVHg8vgGBfofPpAEAAA/LyTSl9fqayi6ul9lUsDAlDXviWBFqa5wCvTOqE3xye4

    Keep your Indeed profile up to date
    Marek Kujawa
    Edit profile: https://cts.indeed.com/v3/H4sIAAAAAAAA_z2OywqDMBRE_yULV4012peCFLqR7rsv8Xo1qXlIvBaK9N-bQulqYM4wMytbWMUU0TRX2-0UfK8Nptp1iF0K3p774G398K3O5T2KlQSKB5RA-ilJe8fR8eZyRyu1ScDXzSVRpkbHNsyyamUSwC-Orl3cEWUhDsdSFNk-YjAaxpsKfhlUhBQW_LuvCaM1WxmI9_FLK2Hk2Gniv48xSeO3ctz1jzwTrRny4ZQJ9n5_AAY1Qt3UAAAA/XuimjAffmzYjcORO0WX_be8i2c8YLPT_PkC-yqG7uKw
    Minimum base pay: https://cts.indeed.com/v3/H4sIAAAAAAAA_z2OTWvDMBBE_4sOPlWJ5fQrBlPIJfTee1ivV5ZiSSvkdSGE_PeqFHoaeANv5q421Ssnktd-v8-FrQ-082kimnbIsSKyVCghrR-2cByuPPoOLjUiCDpdCFD8N4jnpCnp8-lCEXxokIfzqXFhoNRwpjRkuKknFVV_V4DIW5LPqY6b48G8vh3NoX2pNQaPy5crvM2ullI2-qe3TBWtEYpoWw-OgIv-s8rya1qe7bVrzRjmbn5vjXo8fgDBkfiN4AAAAA/WibLknqZbuSf7TdyJMlu1vd8lQGuAY74hIXhj9_6HQI

    This job match email is provided by the employer posting this job on Indeed.
    This message is intended only for you. Do not forward this email.
    Manage email settings: https://cts.indeed.com/v3/H4sIAAAAAAAA_12OzarCMBBG3yWLrqxt6s_VQrkgXMS17iVOp8nYJpF0Ioj47kYRF3c1cL7hcO4iiloY5stYF8WIEANOybWI7RS8TYSZnB4L55k6AsXk3fjLfSP7eXeuSnkadKVXpczAN9tNZoYGXdYFb5uzP1GljulYxWDygAqYrm9Fji7fbo5oFQ1iIqyo70IB-Oh416YiuZ7J5c9azspFmmEg6A8m-KhNGjlE_NLbBROyyimNfy_d_pOcPrh_qf6FisfjCZMyCHD2AAAA/jywcMj61NuaG6asvqe0zClt_UyiRPj5x59xtO6BFjME
    Help Centre: https://cts.indeed.com/v3/H4sIAAAAAAAA_z2NSw7CIBQA7_LWWqD1V5LGtXsvYB8IFQqEPham6d3FxLidyWRWKCDBEqVFMraUlGKmZgpKa9VgnJlFpsPejFfrBx1gBzPIFR6IsQS6qRqLvhOncy86fqwa_YTubnMsxlZJueg_fSdd0W9SKblv7g7PV8vF6E1rLlzAtn0Af1-YUZUAAAA/CIA0caHV_q2_YO8h-CifPm6P76l6_Z8Qj1I_QT1l0g0

    Indeed
    Help Centre: https://cts.indeed.com/v3/H4sIAAAAAAAA_z2NSw7CIBQA7_LWWqD1V5LGtXsvYB8IFQqEPham6d3FxLidyWRWKCDBEqVFMraUlGKmZgpKa9VgnJlFpsPejFfrBx1gBzPIFR6IsQS6qRqLvhOncy86fqwa_YTubnMsxlZJueg_fSdd0W9SKblv7g7PV8vF6E1rLlzAtn0Af1-YUZUAAAA/CIA0caHV_q2_YO8h-CifPm6P76l6_Z8Qj1I_QT1l0g0
    Privacy Policy: https://cts.indeed.com/v3/H4sIAAAAAAAA_z2Myw7CIBQF_-W6NQKtrzYxrt37A_SCgFAgFEyapv8uJo3bmXNmgQI96Jzj1BOiU5aoYzIfjvMBw0iGxL2YiPFCSnHX7ib9bvMxOIMz7GGEfgGOGIrPD1FzrGvZ-dKxlp6qxjqzT51CUbrKnIr80znKirZgpdn-7vb4ejeUDU416koZrOsXh-AE7KcAAAA/qTXrM2Ny5RB2U0leBd0r8UEp1UD27iaivyOis5rqno8
    Terms: https://cts.indeed.com/v3/H4sIAAAAAAAA_z2MSw6DIBQA7_K6bQS0P0lM1933AhZewfIz-Fg0xrtXNt3OZGaFAhIs0bxIxoprpqgRdaNSYB7N6O_WDxgPlBY4QgC5wqhUKpEeeg9F34nLtRcdP-9a-Um5p82pGLtLygX_9DtjRZhDHZGrsTu9Py0XL29ac-MCtu0HpBzbZo8AAAA/mqwHcilX83Isv4v1uO6ik2pUeAZTCSTNnJ6fAIQsEvA
    Unsubscribe: https://cts.indeed.com/v3/H4sIAAAAAAAA_12RXW-iQABF_wvJ-lQqiICYkI1Ai1AsIIrgC2EGZPiQUZhRbNP_Xpo0-7DJfbonubnJ-WQos2QQIZd-OZ32FPSwKy-kxG3_XLZZnmfPEJ-n-EIwJX8hVk1tgho1byekVvl6fqpmHA-aYlYsOH4CCVH1Uvtgr4PIEoP3NG8Og_gSY0kJHjrfR_o92AN8WOm9mMtOMlhFkJ9rscNvUPM8-_1jcDJqbN258cDC1jBitrYG2SxRtUrj9MWDbzu39z3n1Wmj1CocdMwi7o9gTAiu81bVax1d7bvtATn2DgtN6HP2Gj6EDNRd425Y0NSpRARQKVsoB_rJ3BcW35MjEuYLoFfpojWqZCee5ZUbrm8ryStm5kBl9qU05Bbxm_Xp1kgmBpFCog24RXaR7BM342K8S6V24999cEwR9sPw4Cj7V5rYNj1wazO0-uzdH3-OYZ6YM7P8ZFIIMW2JlY0CeEXgJVnhBU4cMWxKWO9Qh2mBRkg6mv9rH5d8rGj7qwr8EFL_TPwng_n6-gb_-nP53QEAAA/g3mD9SHIa9qz6S9r_SC5pZ8goBGPN60_1WpCtq8eJYA
    """

    static func context(
        longBody: Bool = false,
        emptyAttachments: Bool = true
    ) -> ConditionalAccessPromptContext {
        let body = longBody ? longPlainBody : MailMIME.plainText(fromHTML: htmlBody)
        var fields: [ConditionalFieldPreviewLine] = [
            ConditionalFieldPreviewLine(label: "Body", value: body),
        ]
        if emptyAttachments {
            fields.append(ConditionalFieldPreviewLine(label: "Attachment names", value: "(empty)"))
            fields.append(ConditionalFieldPreviewLine(label: "Attachment content", value: "(empty)"))
        } else {
            fields.append(ConditionalFieldPreviewLine(label: "Attachment names", value: "offer.pdf\nresume.docx"))
            fields.append(ConditionalFieldPreviewLine(label: "Attachment content", value: "(empty)"))
        }
        return ConditionalAccessPromptContext(
            agentID: "sandbox-agent",
            agentName: "Cursor",
            accountID: "19DAAEEB-B0A9-4C37-820B-A55EC8B979CB",
            placement: "INBOX",
            messageID: longBody ? "ask-sandbox-long" : "ask-sandbox",
            internetMessageID: "<sample@mailgent.local>",
            requestedFields: fields.map(\.label),
            fieldPreviews: fields,
            htmlBody: longBody ? nil : htmlBody,
            envelope: ConditionalMessageEnvelope(
                subject: longBody
                    ? "Senior Embedded Software Engineer at Bramah Safeguarding CIC"
                    : "1 new job based on your recent activity",
                from: longBody
                    ? "Indeed <noreply@indeed.com>"
                    : "Will Aylott <will@example.com>",
                to: "Marek <you@icloud.com>",
                cc: "",
                date: "Thu, 8 Oct 2026"
            )
        )
    }

    static func request(longBody: Bool = false, emptyAttachments: Bool = true) -> ConditionalAccessPromptRequest {
        ConditionalAccessPromptRequest(context: context(longBody: longBody, emptyAttachments: emptyAttachments))
    }
}

#Preview("Ask dialog") {
    ConditionalAccessPromptDialog(
        request: AskLayoutSandboxSamples.request(),
        accountLabel: "iCloud",
        onAllow: {},
        onBlock: {},
        showOpenInMail: true,
        onOpenInMail: {}
    )
    .frame(
        width: ConditionalAskLayout.expandedWidth,
        height: ConditionalAskLayout.dialogHeight
    )
    .background(Color(nsColor: .windowBackgroundColor))
}

#Preview("Ask compact") {
    ConditionalAccessPromptDialog(
        request: AskLayoutSandboxSamples.request(),
        accountLabel: "iCloud",
        onAllow: {},
        onBlock: {},
        showOpenInMail: true,
        onOpenInMail: {},
        showsMessagePreview: false
    )
    .frame(
        width: ConditionalAskLayout.compactWidth,
        height: ConditionalAskLayout.dialogHeight
    )
    .background(Color(nsColor: .windowBackgroundColor))
}

#Preview("Ask long body + empty attach") {
    ConditionalAccessPromptDialog(
        request: AskLayoutSandboxSamples.request(longBody: true),
        accountLabel: "iCloud",
        onAllow: {},
        onBlock: {},
        showOpenInMail: true,
        onOpenInMail: {}
    )
    .frame(
        width: ConditionalAskLayout.expandedWidth,
        height: ConditionalAskLayout.dialogMinHeight
    )
    .background(Color(nsColor: .windowBackgroundColor))
}
#endif
