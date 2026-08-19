import AppKit
import MailStore
import SwiftUI

/// Landing is access health and placements. Search is a deliberate destination.
struct VariantControlFirst: View {
    @Bindable var session: PrototypeReadSession

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Control center")
                            .font(.largeTitle.bold())
                        Text("Safety and ingest first. Mail search is a separate step.")
                            .foregroundStyle(.secondary)
                    }

                    HStack(alignment: .top, spacing: 16) {
                        healthCard
                        ingestCard
                    }

                    VStack(alignment: .leading, spacing: 10) {
                        Text("Placements")
                            .font(.headline)
                        ForEach(session.placements, id: \.rowID) { placement in
                            Button {
                                session.selectedPlacement = placement
                                session.query = ""
                                session.refresh()
                            } label: {
                                HStack {
                                    SourceChip(accountID: placement.accountID, placement: placement.id)
                                    Spacer()
                                    Image(systemName: "chevron.right")
                                        .foregroundStyle(.tertiary)
                                }
                                .padding(12)
                                .background(.background, in: RoundedRectangle(cornerRadius: 10))
                                .overlay {
                                    RoundedRectangle(cornerRadius: 10)
                                        .stroke(.separator)
                                }
                            }
                            .buttonStyle(.plain)
                        }
                    }

                    NavigationLink("Search mail") {
                        ControlSearchPage(session: session)
                    }
                    .buttonStyle(.borderedProminent)
                }
                .padding(24)
                .padding(.bottom, 48)
            }
            .background(Color(nsColor: .windowBackgroundColor))
        }
    }

    private var healthCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Access health")
                .font(.headline)
            Text(session.mailAccessGranted ? "Full Disk Access granted" : "Grant access to Mail")
                .foregroundStyle(session.mailAccessGranted ? .green : .orange)
            Text("Companion will not write Apple Mail’s store.")
                .font(.caption)
                .foregroundStyle(.secondary)
            if !session.mailAccessGranted {
                Button("Open grant settings…") {
                    session.access.openFullDiskAccessSettings()
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.background, in: RoundedRectangle(cornerRadius: 12))
        .overlay {
            RoundedRectangle(cornerRadius: 12).stroke(.separator)
        }
    }

    private var ingestCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Last ingest")
                .font(.headline)
            Text(session.lastIngestAt?.formatted(date: .abbreviated, time: .shortened) ?? "Never")
            Text("\(session.lastNewCount) new · \(session.source.title)")
                .foregroundStyle(.secondary)
            HStack {
                Button("Reindex now", action: session.ingestAgain)
                if session.mailAccessGranted {
                    Button(session.source == .liveMail ? "Use fixture" : "Use live Mail") {
                        session.setSource(session.source == .liveMail ? .fixture : .liveMail)
                    }
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.background, in: RoundedRectangle(cornerRadius: 12))
        .overlay {
            RoundedRectangle(cornerRadius: 12).stroke(.separator)
        }
    }
}

private struct ControlSearchPage: View {
    @Bindable var session: PrototypeReadSession

    var body: some View {
        List(session.items, id: \.rowID) { message in
            NavigationLink {
                ControlReadPage(session: session, message: message)
            } label: {
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(message.subject.isEmpty ? "(no subject)" : message.subject)
                            .font(.headline)
                        if message.isPartial { PartialBadge() }
                    }
                    Text(message.from)
                    SourceChip(accountID: message.accountID, placement: message.placement)
                }
                .padding(.vertical, 4)
            }
        }
        .navigationTitle("Search mail")
        .searchable(text: $session.query, prompt: "Find across accounts")
        .onSubmit(of: .search, session.refresh)
        .onChange(of: session.query) { _, _ in
            if session.query.isEmpty { session.refresh() }
        }
        .toolbar {
            PlacementMenu(session: session)
        }
        .onAppear(perform: session.refresh)
    }
}

private struct ControlReadPage: View {
    @Bindable var session: PrototypeReadSession
    let message: IndexedMessage

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                if let detail = session.detail {
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
                } else {
                    Text("Message not available")
                        .foregroundStyle(.secondary)
                }
            }
            .padding(24)
        }
        .onAppear { session.select(message) }
    }
}
