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

    var body: some View {
        VStack(alignment: .leading, spacing: ConditionalAskLayout.gap) {
            lead
            if let resolved = resolvedContext {
                splitContent(resolved)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            } else {
                envelopeCard
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
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

                bodyPreview
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
    }

    private var bodyPreview: some View {
        ZStack {
            MessageBodyView(
                readBody: bodyLooksLikeHTML ? .text("") : .text(proposal.body),
                htmlBody: bodyLooksLikeHTML ? proposal.body : nil,
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
            Spacer(minLength: 8)

            Button("Cancel") { onCancel() }
                .buttonStyle(AskPrimaryFooterButtonStyle(prominent: false))
                .keyboardShortcut(.cancelAction)

            Button("Open in Mail") { onOpenInMail() }
                .buttonStyle(AskPrimaryFooterButtonStyle(prominent: false))

            Button("Send") { onSend() }
                .buttonStyle(AskPrimaryFooterButtonStyle(prominent: true))
                .keyboardShortcut(.defaultAction)
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
