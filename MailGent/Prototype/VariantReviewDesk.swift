import AppKit
import MailStore
import SwiftUI

/// One queue beside an inspector. Placement is a filter, not a mailbox tree.
struct VariantReviewDesk: View {
    @Bindable var session: PrototypeReadSession

    var body: some View {
        HSplitView {
            VStack(alignment: .leading, spacing: 0) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Review queue")
                        .font(.title2.bold())
                    HStack {
                        TextField("Filter queue", text: $session.query)
                            .textFieldStyle(.roundedBorder)
                            .onSubmit(session.refresh)
                        PlacementMenu(session: session)
                    }
                    Text("\(session.items.count) items · \(session.source.title)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(14)
                List(session.items, id: \.rowID, selection: selection) { message in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(message.subject.isEmpty ? "(no subject)" : message.subject)
                            .font(.headline)
                        Text(message.from)
                            .font(.subheadline)
                        HStack {
                            SourceChip(accountID: message.accountID, placement: message.placement)
                            if message.isPartial { PartialBadge() }
                        }
                    }
                    .padding(.vertical, 6)
                    .tag(message.rowID)
                }
                .listStyle(.plain)
            }
            .frame(minWidth: 280)

            Group {
                if let detail = session.detail {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 14) {
                            Text("Inspector")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)
                            Text(detail.subject.isEmpty ? "(no subject)" : detail.subject)
                                .font(.title.bold())
                            SourceChip(accountID: detail.accountID, placement: detail.placement)
                            if detail.isPartial { PartialBadge() }
                            Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 6) {
                                GridRow {
                                    Text("From").foregroundStyle(.secondary)
                                    Text(detail.from)
                                }
                                GridRow {
                                    Text("To").foregroundStyle(.secondary)
                                    Text(detail.to)
                                }
                                GridRow {
                                    Text("Date").foregroundStyle(.secondary)
                                    Text(detail.date)
                                }
                            }
                            Divider()
                            MessageBodyView(readBody: detail.body)
                            OpenInMailButton(session: session)
                        }
                        .padding(24)
                    }
                    .background(Color(nsColor: .textBackgroundColor))
                } else {
                    ContentUnavailableView(
                        "Nothing selected",
                        systemImage: "doc.text.magnifyingglass",
                        description: Text("Pick a queue item to inspect it here.")
                    )
                }
            }
            .frame(minWidth: 360)
        }
        .onAppear {
            session.refresh()
            if session.detail == nil, let first = session.items.first {
                session.select(first)
            }
        }
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
