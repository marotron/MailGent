import SwiftUI

/// B — MailGent-owned version history; copy still exits via clipboard. No Mail-store write.
struct VariantDraftLedger: View {
    @Bindable var session: PrototypeDraftSession

    var body: some View {
        HSplitView {
            versionRail
                .frame(minWidth: 180, idealWidth: 200)

            VStack(alignment: .leading, spacing: 16) {
                header
                sourceStrip
                composer
                actionRow
                Spacer(minLength: 0)
            }
            .padding(24)
            .frame(minWidth: 360)

            statePane
                .frame(minWidth: 240, idealWidth: 280)
        }
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Versioned draft ledger")
                .font(.largeTitle.bold())
            Text("Save revisions here. Copy the current version when you are ready to paste into Mail.app.")
                .foregroundStyle(.secondary)
        }
    }

    private var sourceStrip: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text("Re:")
                .foregroundStyle(.secondary)
            Text(session.source.subject)
                .fontWeight(.semibold)
            Text("·")
                .foregroundStyle(.tertiary)
            Text(session.source.accountLabel)
                .foregroundStyle(.secondary)
            Spacer()
        }
        .font(.callout)
        .padding(12)
        .background(.background, in: RoundedRectangle(cornerRadius: 8))
        .overlay {
            RoundedRectangle(cornerRadius: 8).stroke(.separator)
        }
    }

    private var versionRail: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("History")
                .font(.headline)
                .padding(.horizontal, 12)
                .padding(.top, 16)
            if session.versions.isEmpty {
                Text("No versions yet.\nSave to start the ledger.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 12)
                    .padding(.top, 4)
                Spacer(minLength: 0)
            } else {
                ScrollView {
                    LazyVStack(spacing: 6) {
                        ForEach(session.versions) { version in
                            let selected = version.id == session.selectedVersionID
                            Button {
                                session.selectVersion(version.id)
                            } label: {
                                VStack(alignment: .leading, spacing: 4) {
                                    HStack(alignment: .firstTextBaseline) {
                                        Text(version.label)
                                            .font(.body.weight(.semibold))
                                        Spacer(minLength: 8)
                                        Text(version.savedAt.formatted(date: .omitted, time: .shortened))
                                            .font(.caption)
                                            .foregroundStyle(selected ? AnyShapeStyle(.white.opacity(0.85)) : AnyShapeStyle(.secondary))
                                    }
                                    Text(version.body.replacingOccurrences(of: "\n", with: " "))
                                        .font(.caption)
                                        .foregroundStyle(selected ? AnyShapeStyle(.white.opacity(0.9)) : AnyShapeStyle(.secondary))
                                        .lineLimit(2)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                }
                                .padding(.horizontal, 10)
                                .padding(.vertical, 8)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(
                                    selected ? AnyShapeStyle(Color.accentColor) : AnyShapeStyle(.clear),
                                    in: RoundedRectangle(cornerRadius: 8)
                                )
                                .foregroundStyle(selected ? .white : .primary)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 8)
                    .padding(.bottom, 12)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private var composer: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Current draft")
                    .font(.headline)
                Spacer()
                if let selected = session.selectedVersion {
                    Text("editing \(selected.label)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            TextEditor(text: $session.draftText)
                .font(.body)
                .scrollContentBackground(.hidden)
                .padding(10)
                .frame(minHeight: 200)
                .background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 10))
                .overlay {
                    RoundedRectangle(cornerRadius: 10).stroke(.separator)
                }
                .onChange(of: session.draftText) { _, _ in
                    session.note("edited draft (\(session.draftText.count) chars)")
                }
        }
    }

    private var actionRow: some View {
        HStack {
            Button("Save version") {
                session.saveLedgerVersion()
            }
            .buttonStyle(.borderedProminent)
            Button("Copy current") {
                session.copyCurrentLedgerVersion()
            }
            Button("Open Mail.app") {
                session.openMailApp()
            }
            Spacer()
        }
    }

    private var statePane: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("State")
                .font(.headline)
            Text("Ledger + clipboard after each action.")
                .font(.caption)
                .foregroundStyle(.secondary)
            ScrollView {
                Text(session.stateDump)
                    .font(.system(.caption, design: .monospaced))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            if !session.versions.isEmpty {
                Divider()
                Text("Versions")
                    .font(.subheadline.weight(.semibold))
                ForEach(session.versions) { version in
                    Text("\(version.label) · \(version.body.count) chars · \(version.savedAt.formatted(date: .omitted, time: .shortened))")
                        .font(.system(.caption2, design: .monospaced))
                        .foregroundStyle(version.id == session.selectedVersionID ? .primary : .secondary)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(20)
        .background(Color(nsColor: .controlBackgroundColor))
    }
}
