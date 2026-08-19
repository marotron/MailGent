import MailStore
import SwiftUI

struct SourceChip: View {
    let accountID: String
    let placement: String

    var body: some View {
        HStack(spacing: 6) {
            Text(PrototypeAccounts.label(accountID))
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

    var body: some View {
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

struct OpenInMailButton: View {
    var session: PrototypeReadSession

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
    @Bindable var session: PrototypeReadSession

    var body: some View {
        Menu(session.selectedPlacement.map {
            "\(PrototypeAccounts.label($0.accountID)) · \($0.id)"
        } ?? "All placements") {
            Button("All placements") {
                session.selectedPlacement = nil
                session.refresh()
            }
            ForEach(session.placements, id: \.rowID) { placement in
                Button("\(PrototypeAccounts.label(placement.accountID)) · \(placement.id)") {
                    session.selectedPlacement = placement
                    session.refresh()
                }
            }
        }
    }
}
