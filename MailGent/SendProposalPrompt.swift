import AppKit
import MailStore
import SwiftUI

/// Confirm dialog for MCP `propose_send`. Ask chrome + Variant B body preview
/// (card fills to footer; Formatted|Raw overlays the body on hover).
struct SendProposalPromptDialog: View {
    let proposal: SendProposal
    let onSend: () -> Void
    let onOpenInMail: () -> Void
    let onCancel: () -> Void

    @State private var showRaw = false
    @State private var bodyHovered = false

    private static let envelopeLabelWidth: CGFloat = 52

    /// Default / min window sizes (CompanionWindow clamps max height ~900).
    static let windowSize = NSSize(width: 560, height: 620)
    static let windowMinSize = NSSize(width: 480, height: 420)

    private var bodyLooksLikeHTML: Bool {
        MailMIME.bodyLooksLikeHTML(proposal.body)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: ConditionalAskLayout.gap) {
            lead
            envelopeCard
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            footer
        }
        .padding(ConditionalAskLayout.pad)
        .frame(
            minWidth: Self.windowMinSize.width,
            idealWidth: Self.windowSize.width,
            maxWidth: .infinity,
            minHeight: Self.windowMinSize.height,
            idealHeight: Self.windowSize.height,
            maxHeight: .infinity,
            alignment: .topLeading
        )
    }

    private var lead: some View {
        HStack(alignment: .center, spacing: 8) {
            Image(systemName: "paperplane.fill")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(.orange)
            Text("\(proposal.agentName) wants to send this message via Apple Mail")
                .font(.callout.weight(.medium))
                .foregroundStyle(.secondary)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
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
        ZStack(alignment: .topTrailing) {
            MessageBodyView(
                readBody: bodyLooksLikeHTML ? .text("") : .text(proposal.body),
                htmlBody: bodyLooksLikeHTML ? proposal.body : nil,
                rawBody: proposal.body,
                showRaw: showRaw,
                ensureReadableInsets: true
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)

            if bodyHovered {
                FormattedRawModeSegments(showRaw: $showRaw)
                    .padding(10)
                    .shadow(color: .black.opacity(0.12), radius: 6, y: 2)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .contentShape(Rectangle())
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.15)) {
                bodyHovered = hovering
            }
        }
        .accessibilityElement(children: .contain)
    }

    private var footer: some View {
        HStack(spacing: 8) {
            Button("Cancel") { onCancel() }
                .buttonStyle(AskPrimaryFooterButtonStyle(prominent: false))
                .keyboardShortcut(.cancelAction)

            Button("Open in Mail") { onOpenInMail() }
                .buttonStyle(AskPrimaryFooterButtonStyle(prominent: false))

            Spacer(minLength: 8)

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
