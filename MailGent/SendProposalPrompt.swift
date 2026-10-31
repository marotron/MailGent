import AppKit
import MailStore
import SwiftUI

/// Confirm dialog for MCP `propose_send`. Ask chrome + Variant B body preview
/// (card fills to footer; Formatted|Raw overlays the body on hover).
/// When experimental context is resolved, shows E-thin × F-full × P4 split.
struct SendProposalPromptDialog: View {
    let proposal: SendProposal
    let resolvedContext: ProposeSendResolvedContext?
    let onSend: () -> Void
    let onOpenInMail: () -> Void
    let onCancel: () -> Void
    var onOpenContextOriginal: (ContextThreadOriginal) -> Void = { _ in }

    @State private var showRaw = false
    @State private var bodyHovered = false
    @State private var pageZoom: CGFloat = Self.defaultZoom
    @State private var contextThin = true
    @State private var selectedEventID: String? = "draft"
    @State private var spotlightDraft = true

    private static let envelopeLabelWidth: CGFloat = 52
    private static let defaultZoom: CGFloat = 0.75
    private static let zoomStep: CGFloat = 0.25
    private static let minZoom: CGFloat = 0.5
    private static let maxZoom: CGFloat = 1.5

    /// Default / min window sizes (CompanionWindow clamps max height ~900).
    static let windowSize = NSSize(width: 560, height: 620)
    static let windowMinSize = NSSize(width: 480, height: 420)
    static let contextWindowSize = NSSize(width: 820, height: 640)
    static let contextWindowMinSize = NSSize(width: 700, height: 480)

    private var showsContext: Bool { resolvedContext != nil }

    private var bodyLooksLikeHTML: Bool {
        MailMIME.bodyLooksLikeHTML(proposal.body)
    }

    private var hasSecretHighlights: Bool {
        !proposal.secretConstantSpans.isEmpty && !bodyLooksLikeHTML
    }

    private var secretHighlightHTML: String? {
        guard hasSecretHighlights else { return nil }
        return SecretConstantHighlight.html(
            resolved: proposal.body,
            spans: proposal.secretConstantSpans
        )
    }

    private var secretConstantsBlocked: Bool {
        !proposal.secretConstantMissing.isEmpty
    }

    /// Unique secrets in body order — for the strip under the preview.
    private var usedSecretSummaries: [UsedSecretSummary] {
        var order: [String] = []
        var byName: [String: UsedSecretSummary] = [:]
        let chars = Array(proposal.body)
        for span in proposal.secretConstantSpans.sorted(by: { $0.start < $1.start }) {
            let start = max(0, min(span.start, chars.count))
            let end = max(start, min(span.end, chars.count))
            let value = String(chars[start..<end])
            if var existing = byName[span.name] {
                existing.updated = existing.updated || span.updatedSinceDraft
                if existing.value.isEmpty, !value.isEmpty {
                    existing.value = value
                }
                byName[span.name] = existing
            } else {
                order.append(span.name)
                byName[span.name] = UsedSecretSummary(
                    name: span.name,
                    value: value,
                    updated: span.updatedSinceDraft
                )
            }
        }
        return order.compactMap { byName[$0] }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: ConditionalAskLayout.gap) {
            lead
            if secretConstantsBlocked {
                secretMissingBanner
            }
            if let resolved = resolvedContext {
                splitContent(resolved)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            } else {
                envelopeCard
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
            if !usedSecretSummaries.isEmpty {
                secretUsedStrip
            }
            footer
        }
        .padding(ConditionalAskLayout.pad)
        .frame(
            minWidth: (showsContext ? Self.contextWindowMinSize : Self.windowMinSize).width,
            idealWidth: (showsContext ? Self.contextWindowSize : Self.windowSize).width,
            maxWidth: .infinity,
            minHeight: (showsContext ? Self.contextWindowMinSize : Self.windowMinSize).height,
            idealHeight: (showsContext ? Self.contextWindowSize : Self.windowSize).height,
            maxHeight: .infinity,
            alignment: .topLeading
        )
    }

    private var lead: some View {
        HStack(alignment: .center, spacing: 8) {
            Image(systemName: "paperplane.fill")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(.orange)
            VStack(alignment: .leading, spacing: 2) {
                Text("\(proposal.agentName) wants to send this message via Apple Mail")
                    .font(.callout.weight(.medium))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                if showsContext {
                    Text(spotlightDraft ? "Draft ready" : "In focus")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(spotlightDraft ? .orange : .secondary)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func splitContent(_ resolved: ProposeSendResolvedContext) -> some View {
        HStack(alignment: .top, spacing: 10) {
            SendProposalContextThreadView(
                resolved: resolved,
                thin: $contextThin,
                selectedID: $selectedEventID,
                spotlightDraft: $spotlightDraft,
                onOpenOriginal: onOpenContextOriginal
            )
            .frame(width: contextThin ? 124 : nil)
            .frame(maxWidth: contextThin ? 124 : .infinity, maxHeight: .infinity)

            envelopeCard
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .strokeBorder(
                            spotlightDraft ? Color.primary.opacity(0.45) : Color.clear,
                            lineWidth: 1.5
                        )
                )
                .onTapGesture {
                    selectedEventID = "draft"
                    spotlightDraft = true
                }
        }
    }

    private var envelopeCard: some View {
        ConditionalAskCard {
            VStack(alignment: .leading, spacing: ConditionalAskLayout.gap / 2) {
                if let sender = proposal.sender?.trimmingCharacters(in: .whitespacesAndNewlines),
                   !sender.isEmpty
                {
                    envelopeAddressRow(label: "From", raw: sender)
                }
                envelopeAddressRow(label: "To", raw: proposal.to.joined(separator: ", "))
                if !proposal.cc.isEmpty {
                    envelopeAddressRow(label: "Cc", raw: proposal.cc.joined(separator: ", "))
                }
                if !proposal.bcc.isEmpty {
                    envelopeAddressRow(label: "Bcc", raw: proposal.bcc.joined(separator: ", "))
                }
                envelopeRow(label: "Subject", value: proposal.subject)

                Divider().opacity(0.35)

                if proposal.secretConstantSpans.contains(where: \.updatedSinceDraft) {
                    Text("Some secret constants were updated since this draft was written.")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }

                bodyPreview
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
    }

    private var secretMissingBanner: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
            VStack(alignment: .leading, spacing: 2) {
                Text("Unknown secret constants")
                    .font(.caption.weight(.semibold))
                Text(proposal.secretConstantMissing.map { "[[mg:\($0)]]" }.joined(separator: ", "))
                    .font(.caption2.monospaced())
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    /// Between body preview and Cancel / Open / Send — orangy marks mean “replaced secret”.
    private var secretUsedStrip: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: "key.fill")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
                Text("Secret constants replaced for send")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            FlowUsedSecrets(summaries: usedSecretSummaries)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Secret constants replaced for send")
    }

    private var bodyPreview: some View {
        ZStack {
            MessageBodyView(
                readBody: bodyLooksLikeHTML || hasSecretHighlights ? .text("") : .text(proposal.body),
                htmlBody: secretHighlightHTML ?? (bodyLooksLikeHTML ? proposal.body : nil),
                rawBody: proposal.body,
                showRaw: showRaw,
                pageZoom: pageZoom,
                ensureReadableInsets: true
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .clipped()

            // AppKit tracker: WKWebView / NSScrollView eat SwiftUI onHover.
            AskPreviewHoverTracker(isHovering: $bodyHovered)
                .allowsHitTesting(false)

            FormattedRawModeSegments(showRaw: $showRaw)
                .padding(.top, 8)
                .padding(.trailing, 10)
                .shadow(color: .black.opacity(0.12), radius: 6, y: 2)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                .opacity(bodyHovered ? 1 : 0)
                .allowsHitTesting(bodyHovered)
                .accessibilityHidden(!bodyHovered)
                .onHover { hovering in
                    if hovering { bodyHovered = true }
                }
                .transition(.opacity.combined(with: .move(edge: .top)))

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
            .padding(.trailing, 10)
            .padding(.bottom, 8)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
            .opacity(bodyHovered ? 1 : 0)
            .allowsHitTesting(bodyHovered)
            .accessibilityHidden(!bodyHovered)
            .onHover { hovering in
                if hovering { bodyHovered = true }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Message preview")
        .accessibilityValue("\(Int((pageZoom * 100).rounded())) percent")
    }

    private var footer: some View {
        HStack(spacing: 8) {
            Button("Cancel") { onCancel() }
                .buttonStyle(AskPrimaryFooterButtonStyle(prominent: false))
                .keyboardShortcut(.cancelAction)

            Spacer(minLength: 8)

            Button("Open in Mail") { onOpenInMail() }
                .buttonStyle(AskPrimaryFooterButtonStyle(prominent: false))
                .disabled(secretConstantsBlocked)

            Button("Send") { onSend() }
                .buttonStyle(AskPrimaryFooterButtonStyle(prominent: true))
                .keyboardShortcut(.defaultAction)
                .disabled(secretConstantsBlocked)
        }
    }

    private func envelopeLabel(_ label: String) -> some View {
        Text(label)
            .font(.caption2)
            .foregroundStyle(.secondary)
            .frame(width: Self.envelopeLabelWidth, alignment: .leading)
            .textSelection(.enabled)
    }

    private func envelopeRow(label: String, value: String) -> some View {
        HStack(alignment: .center, spacing: 8) {
            envelopeLabel(label)
            Text(value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "—" : value)
                .font(.caption2)
                .textSelection(.enabled)
                .lineLimit(3)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

}

private struct UsedSecretSummary: Equatable, Identifiable {
    var name: String
    var value: String
    var updated: Bool
    var id: String { name }
}

/// Compact wrapping chips: `[[mg:name]] → value` (orangy value matches body `<mark>`).
private struct FlowUsedSecrets: View {
    let summaries: [UsedSecretSummary]

    var body: some View {
        // Simple wrap without a custom layout type — enough for ~10 constants.
        VStack(alignment: .leading, spacing: 4) {
            ForEach(summaries) { summary in
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text("[[mg:\(summary.name)]]")
                        .font(.caption2.monospaced())
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                    Image(systemName: "arrow.right")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundStyle(.tertiary)
                    Text(summary.value.isEmpty ? "—" : summary.value)
                        .font(.caption2.weight(.medium))
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1)
                        .background(Color.orange.opacity(0.35), in: RoundedRectangle(cornerRadius: 3, style: .continuous))
                        .textSelection(.enabled)
                    if summary.updated {
                        Text("updated")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.orange)
                    }
                }
                .accessibilityElement(children: .combine)
                .accessibilityLabel(
                    summary.updated
                        ? "\(summary.name) replaced with \(summary.value), updated since draft"
                        : "\(summary.name) replaced with \(summary.value)"
                )
            }
        }
    }
}

extension SendProposalPromptDialog {
    private func envelopeAddressRow(label: String, raw: String) -> some View {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        let addresses = MailAddressParts.parseList(trimmed)
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
        }
    }
}
