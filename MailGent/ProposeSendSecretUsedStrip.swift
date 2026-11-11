import MailStore
import SwiftUI

/// Between body and Cancel / Open / Send — orangy marks mean “replaced secret”.
struct ProposeSendSecretUsedStrip: View {
    let summaries: [ProposeSendUsedSecretSummary]

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: "key.fill")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
                Text("Secret constants replaced for send")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            FlowUsedSecrets(summaries: summaries)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Secret constants replaced for send")
    }
}

/// Compact wrapping chips: `{{mg:name}} → value` (orangy value matches body `<mark>`).
struct FlowUsedSecrets: View {
    let summaries: [ProposeSendUsedSecretSummary]

    var body: some View {
        // Simple wrap without a custom layout type — enough for ~10 constants.
        VStack(alignment: .leading, spacing: 4) {
            ForEach(summaries) { summary in
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(SecretConstantPlaceholders.token(for: summary.name))
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
