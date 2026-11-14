import SwiftUI

/// Top-slot status banner for confirm dialogs (propose-send phases, Ask expiry).
/// Same chrome everywhere; `tone` picks icon and tint.
struct PhaseBanner: View {
    enum Tone: Equatable {
        case progress
        case success
        case failure
        case neutral
    }

    let tone: Tone
    let title: String
    let subtitle: String

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            icon
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.callout.weight(.semibold))
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(subtitleColor)
                    .fixedSize(horizontal: false, vertical: true)
                    .textSelection(.enabled)
            }
            Spacer(minLength: 0)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(background, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(title). \(subtitle)")
    }

    @ViewBuilder
    private var icon: some View {
        switch tone {
        case .progress:
            ProgressView()
                .controlSize(.small)
                .frame(width: 18, height: 18)
        case .success:
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 18))
                .foregroundStyle(.green)
        case .failure:
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 18))
                .foregroundStyle(.red)
        case .neutral:
            Image(systemName: "clock.badge.xmark")
                .font(.system(size: 18))
                .foregroundStyle(.secondary)
        }
    }

    private var subtitleColor: Color {
        tone == .failure ? .red.opacity(0.85) : .secondary
    }

    private var background: Color {
        switch tone {
        case .progress: Color.accentColor.opacity(0.08)
        case .success: Color.green.opacity(0.10)
        case .failure: Color.red.opacity(0.08)
        case .neutral: Color.secondary.opacity(0.10)
        }
    }
}
