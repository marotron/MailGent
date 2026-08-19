import MailStore
import SwiftUI

/// Landing is find-and-review. Health is a caption, not the home.
struct VariantSearchFirst: View {
    @Bindable var session: PrototypeReadSession

    var body: some View {
        NavigationSplitView {
            VStack(alignment: .leading, spacing: 12) {
                Text("Find mail")
                    .font(.title.bold())
                Text(healthCaption)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                HStack {
                    TextField("Search across accounts", text: $session.query)
                        .textFieldStyle(.roundedBorder)
                        .onSubmit(session.refresh)
                    Button("Search", action: session.refresh)
                        .keyboardShortcut(.defaultAction)
                }
                HStack {
                    PlacementMenu(session: session)
                    Spacer()
                    Text(session.status)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                List(session.items, id: \.rowID, selection: selection) { message in
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text(message.subject.isEmpty ? "(no subject)" : message.subject)
                                .font(.headline)
                            if message.isPartial { PartialBadge() }
                        }
                        Text(message.from)
                            .foregroundStyle(.secondary)
                        SourceChip(accountID: message.accountID, placement: message.placement)
                    }
                    .padding(.vertical, 4)
                    .tag(message.rowID)
                }
            }
            .padding(16)
            .navigationSplitViewColumnWidth(min: 280, ideal: 360)
        } detail: {
            if let detail = session.detail {
                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        Text(detail.subject.isEmpty ? "(no subject)" : detail.subject)
                            .font(.title2.bold())
                        SourceChip(accountID: detail.accountID, placement: detail.placement)
                        if detail.isPartial { PartialBadge() }
                        Text("From \(detail.from)")
                        Text("To \(detail.to)")
                            .foregroundStyle(.secondary)
                        Text(detail.date)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Divider()
                        MessageBodyView(readBody: detail.body)
                        OpenInMailButton(session: session)
                    }
                    .padding(24)
                    .frame(maxWidth: 720, alignment: .leading)
                }
            } else {
                ContentUnavailableView(
                    "Select a message",
                    systemImage: "envelope",
                    description: Text("Search, then pick a hit. Every row shows account and placement.")
                )
            }
        }
        .onAppear(perform: session.refresh)
    }

    private var healthCaption: String {
        let access = session.mailAccessGranted ? "access granted" : "access denied — fixture data"
        let ingest = session.lastIngestAt?.formatted(date: .omitted, time: .shortened) ?? "never"
        return "\(access) · last ingest \(ingest) · \(session.source.title)"
    }

    private var selection: Binding<String?> {
        Binding(
            get: { session.detail?.rowID },
            set: { rowID in
                guard let message = session.items.first(where: { $0.rowID == rowID }) else { return }
                session.select(message)
            }
        )
    }
}
