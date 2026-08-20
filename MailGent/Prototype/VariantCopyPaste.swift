import SwiftUI

/// A — edit reply, copy to clipboard, paste in Mail.app. No MailGent-owned history.
struct VariantCopyPaste: View {
    @Bindable var session: PrototypeDraftSession

    var body: some View {
        HSplitView {
            VStack(alignment: .leading, spacing: 16) {
                header
                sourceCard
                composer
                actionRow
                Spacer(minLength: 0)
            }
            .padding(24)
            .frame(minWidth: 420)

            statePane
                .frame(minWidth: 260, idealWidth: 300)
        }
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Reply → clipboard → Mail.app")
                .font(.largeTitle.bold())
            Text("MailGent never stores this draft. You paste into Apple Mail.")
                .foregroundStyle(.secondary)
        }
    }

    private var sourceCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Replying to")
                .font(.headline)
            Text(session.source.subject)
                .font(.title3.weight(.semibold))
            Text("\(session.source.from) · \(session.source.accountLabel)/\(session.source.placement)")
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(session.source.body)
                .font(.callout)
                .foregroundStyle(.secondary)
                .padding(.top, 4)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.background, in: RoundedRectangle(cornerRadius: 12))
        .overlay {
            RoundedRectangle(cornerRadius: 12).stroke(.separator)
        }
    }

    private var composer: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Your reply")
                .font(.headline)
            TextEditor(text: $session.draftText)
                .font(.body)
                .scrollContentBackground(.hidden)
                .padding(10)
                .frame(minHeight: 180)
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
            Button("Copy reply") {
                session.copyToClipboard()
            }
            .buttonStyle(.borderedProminent)
            Button("Open Mail.app") {
                session.openMailApp()
            }
            Spacer()
            if session.copyCount > 0 {
                Text("Copied \(session.copyCount)× — paste with ⌘V in Mail")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var statePane: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("State")
                .font(.headline)
            Text("Full session after each action.")
                .font(.caption)
                .foregroundStyle(.secondary)
            ScrollView {
                Text(session.stateDump)
                    .font(.system(.caption, design: .monospaced))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            Spacer(minLength: 0)
        }
        .padding(20)
        .background(Color(nsColor: .controlBackgroundColor))
    }
}
