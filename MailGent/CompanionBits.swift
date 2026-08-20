import MailStore
import SwiftUI

struct SourceChip: View {
    let session: CompanionSession
    let accountID: String
    let placement: String

    var body: some View {
        HStack(spacing: 6) {
            Text(session.accountLabel(accountID))
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(.quaternary, in: RoundedRectangle(cornerRadius: 4))
            Text(placement)
                .foregroundStyle(.secondary)
        }
        .font(.caption)
    }
}

struct PartialBadge: View {
    var body: some View {
        Text("Partial")
            .font(.caption2.weight(.semibold))
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .foregroundStyle(.orange)
            .background(.orange.opacity(0.15), in: Capsule())
    }
}

struct MessageBodyView: View {
    let readBody: ReadBody
    var rawBody: String = ""
    @State private var showRaw = false

    private var canToggleRaw: Bool {
        !rawBody.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if canToggleRaw {
                Picker("Body format", selection: $showRaw) {
                    Text("Pretty").tag(false)
                    Text("Raw").tag(true)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(maxWidth: 220)
            }
            bodyContent
                .textSelection(.enabled)
        }
    }

    @ViewBuilder
    private var bodyContent: some View {
        if showRaw, canToggleRaw {
            Text(rawBody)
                .font(.body.monospaced())
        } else {
            switch readBody {
            case .text(let text):
                Text(text)
            case .notAvailable:
                Text("Body not available")
                    .foregroundStyle(.secondary)
                    .italic()
            }
        }
    }
}

struct OpenInMailButton: View {
    var session: CompanionSession

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Button("Open in Apple Mail") {
                session.openInMail()
            }
            if let handoffNote = session.handoffNote {
                Text(handoffNote)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

struct PlacementMenu: View {
    @Bindable var session: CompanionSession

    var body: some View {
        Menu(session.selectedPlacement.map {
            "\(session.accountLabel($0.accountID)) · \($0.id)"
        } ?? "All placements") {
            Button("All placements") {
                session.selectedPlacement = nil
                session.refresh()
            }
            ForEach(session.placements, id: \.rowID) { placement in
                Button("\(session.accountLabel(placement.accountID)) · \(placement.id)") {
                    session.selectedPlacement = placement
                    session.refresh()
                }
            }
        }
    }
}
