import MailStore
import SwiftUI

struct AccessLogView: View {
    @Bindable var session: CompanionSession
    var initialSelection: String?

    @State private var selectedID: String?
    @State private var agentFilter = AgentFilter.all
    @State private var timeFilter = TimeFilter.all
    @State private var confirmClearAll = false
    @State private var confirmClear24h = false

    var body: some View {
        VStack(spacing: 0) {
            filterBar
            Divider()
            HSplitView {
                logList
                    .frame(minWidth: 280, idealWidth: 320, maxHeight: .infinity)
                detailPane
                    .frame(minWidth: 360, maxHeight: .infinity)
            }
        }
        .frame(minWidth: 760, minHeight: 420)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear(perform: applyInitialSelection)
        .onChange(of: session.agents.auditRevision) { _, _ in reconcileSelection() }
        .onChange(of: agentFilter) { _, _ in reconcileSelection() }
        .onChange(of: timeFilter) { _, _ in reconcileSelection() }
        .confirmationDialog(
            "Delete all access logs?",
            isPresented: $confirmClearAll,
            titleVisibility: .visible
        ) {
            Button("Delete all", role: .destructive) {
                session.agents.removeAllAudit()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Removes the full stored log (\(storedCount) entries, \(storedBytesLabel)). This cannot be undone.")
        }
        .confirmationDialog(
            "Delete logs older than 24 hours?",
            isPresented: $confirmClear24h,
            titleVisibility: .visible
        ) {
            Button("Delete older than 24 hours", role: .destructive) {
                session.agents.removeAuditOlderThan24Hours()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Keeps entries from the last 24 hours. Older rows are removed from the stored log.")
        }
    }

    private var entries: [AuditEntry] {
        session.agents.allAudit
    }

    private var storedCount: Int { session.agents.auditStoredCount }
    private var storedBytes: Int { session.agents.auditStoredBytes }

    private var storedBytesLabel: String {
        AccessLogFormat.bytes(storedBytes)
    }

    private var agentNames: [String] {
        Array(Set(entries.map(\.agentName))).sorted()
    }

    private var filtered: [AuditEntry] {
        let now = Date()
        return entries.filter { entry in
            agentFilter.matches(entry.agentName) && timeFilter.contains(entry.at, now: now)
        }
    }

    private var selectedEntry: AuditEntry? {
        filtered.first { $0.id == selectedID }
    }

    private var hasLogsOlderThan24h: Bool {
        let cutoff = Date().addingTimeInterval(-86_400)
        return session.agents.audit.entries().contains { $0.at < cutoff }
    }

    private var filterBar: some View {
        HStack(spacing: 10) {
            Picker("Agent", selection: $agentFilter) {
                Text("All agents").tag(AgentFilter.all)
                ForEach(agentNames, id: \.self) { name in
                    Text(name).tag(AgentFilter.named(name))
                }
            }
            .frame(maxWidth: 180)

            Picker("Time", selection: $timeFilter) {
                ForEach(TimeFilter.allCases) { filter in
                    Text(filter.title).tag(filter)
                }
            }
            .frame(maxWidth: 160)

            Spacer()

            Text(countLabel)
                .font(.caption)
                .foregroundStyle(.secondary)
                .help("Full stored log: \(storedCount) entries, \(storedBytesLabel)")

            Button("Older than 24h") {
                confirmClear24h = true
            }
            .disabled(!hasLogsOlderThan24h)
            .help("Delete stored entries older than 24 hours")

            Button("Delete all", role: .destructive) {
                confirmClearAll = true
            }
            .disabled(storedCount == 0)
        }
        .controlSize(.small)
        .pickerStyle(.menu)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    private var countLabel: String {
        let stored = "\(storedCount) · \(storedBytesLabel)"
        if filtered.count == entries.count {
            return stored
        }
        return "\(filtered.count) of \(stored)"
    }

    private var logList: some View {
        Group {
            if filtered.isEmpty {
                ContentUnavailableView(
                    entries.isEmpty ? "No agent calls yet" : "No matching calls",
                    systemImage: "list.bullet.rectangle",
                    description: Text(
                        entries.isEmpty
                            ? "Paired agent tool calls show up here."
                            : "Try another agent or time range."
                    )
                )
            } else {
                List(filtered, selection: $selectedID) { entry in
                    AccessLogRow(entry: entry)
                        .tag(entry.id)
                }
                .listStyle(.sidebar)
            }
        }
    }

    @ViewBuilder
    private var detailPane: some View {
        if let entry = selectedEntry {
            AccessLogDetail(session: session, entry: entry)
        } else {
            ContentUnavailableView(
                "Select a request",
                systemImage: "doc.text.magnifyingglass",
                description: Text("Pick a row to inspect request, response, and messages.")
            )
        }
    }

    private func applyInitialSelection() {
        if let initialSelection, filtered.contains(where: { $0.id == initialSelection }) {
            selectedID = initialSelection
        } else {
            selectedID = filtered.first?.id
        }
    }

    private func reconcileSelection() {
        if case .named(let name) = agentFilter, !agentNames.contains(name) {
            agentFilter = .all
            return
        }
        if let selectedID, filtered.contains(where: { $0.id == selectedID }) { return }
        self.selectedID = filtered.first?.id
    }

    private enum AgentFilter: Hashable {
        case all
        case named(String)

        func matches(_ name: String) -> Bool {
            switch self {
            case .all: true
            case .named(let expected): name == expected
            }
        }
    }

    private enum TimeFilter: String, CaseIterable, Identifiable {
        case all
        case hour
        case day
        case today

        var id: String { rawValue }

        var title: String {
            switch self {
            case .all: "All time"
            case .hour: "Last hour"
            case .day: "Last 24 hours"
            case .today: "Today"
            }
        }

        func contains(_ date: Date, now: Date) -> Bool {
            switch self {
            case .all: true
            case .hour: date >= now.addingTimeInterval(-3600)
            case .day: date >= now.addingTimeInterval(-86_400)
            case .today: Calendar.current.isDate(date, inSameDayAs: now)
            }
        }
    }
}

private struct AccessLogRow: View {
    let entry: AuditEntry

    var body: some View {
        HStack(alignment: .center, spacing: 8) {
            AuditOutcomeIcon(outcome: entry.outcome)
                .imageScale(.small)
            AuditKindBadge(kind: entry.kind)
            AgentGlyph(name: entry.agentName, size: 16)
            if !entry.detail.isEmpty {
                Text(entry.detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 8)
            Text(timeLabel)
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityText)
    }

    private var timeLabel: String {
        if Calendar.current.isDateInToday(entry.at) {
            return entry.at.formatted(date: .omitted, time: .shortened)
        }
        return entry.at.formatted(date: .numeric, time: .shortened)
    }

    private var accessibilityText: String {
        let status: String
        switch entry.outcome {
        case .ok: status = "succeeded"
        case .error: status = "failed"
        }
        return "\(entry.kind.badgeTitle) \(entry.agentName) \(status)"
    }
}

private struct AccessLogDetail: View {
    @Bindable var session: CompanionSession
    let entry: AuditEntry

    @State private var requestRaw = false
    @State private var responseRaw = false
    @State private var messagesRaw = false
    @State private var placementsRaw = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                header
                togglableField("Request", raw: requestLine, showRaw: $requestRaw) {
                    prettyPairs(requestLine)
                }
                togglableField("Response", raw: responseLine, showRaw: $responseRaw) {
                    prettyResponse
                }
                if !entry.messages.isEmpty {
                    togglableField("Messages", raw: messagesRawText, showRaw: $messagesRaw) {
                        prettyMessages
                    }
                }
                if !entry.placements.isEmpty {
                    togglableField("Placements", raw: placementsRawText, showRaw: $placementsRaw) {
                        prettyPlacements
                    }
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .onChange(of: entry.id) { _, _ in
            requestRaw = false
            responseRaw = false
            messagesRaw = false
            placementsRaw = false
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .center, spacing: 8) {
                AuditKindBadge(kind: entry.kind)
                AgentGlyph(name: entry.agentName, size: 18)
                Text(entry.agentName)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Spacer()
                outcomeBadge
            }
            Text(timingLabel)
                .font(.caption)
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
        }
    }

    @ViewBuilder
    private var outcomeBadge: some View {
        HStack(spacing: 6) {
            AuditOutcomeIcon(outcome: entry.outcome)
            switch entry.outcome {
            case .ok:
                Text("ok")
                    .font(.caption.weight(.semibold).monospaced())
                    .foregroundStyle(.green)
            case .error(let message):
                Text(message.isEmpty ? "error" : message)
                    .font(.caption.weight(.semibold).monospaced())
                    .foregroundStyle(.orange)
                    .lineLimit(2)
            }
        }
    }

    private func togglableField<Pretty: View>(
        _ title: String,
        raw: String,
        showRaw: Binding<Bool>,
        @ViewBuilder pretty: () -> Pretty
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            RawPrettyHeader(title: title, showRaw: showRaw)
            Group {
                if showRaw.wrappedValue {
                    Text(raw)
                        .font(.callout.monospaced())
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                } else {
                    pretty()
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .background(.background, in: RoundedRectangle(cornerRadius: 8))
            .overlay {
                RoundedRectangle(cornerRadius: 8).stroke(.separator)
            }
        }
    }

    @ViewBuilder
    private var prettyResponse: some View {
        if !entry.messages.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    Image(systemName: "list.bullet.rectangle")
                        .foregroundStyle(.secondary)
                    Text("Message list")
                        .font(.callout.weight(.semibold))
                    Text("\(entry.messages.count)")
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                    if let total = messageListTotal, total != entry.messages.count {
                        Text("of \(total)")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                }
                Text("Contained")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                GrantFieldCoverage(fields: listedFields)
            }
        } else if !entry.placements.isEmpty {
            HStack(spacing: 8) {
                Image(systemName: "folder")
                    .foregroundStyle(.secondary)
                Text("Placement list")
                    .font(.callout.weight(.semibold))
                Text("\(entry.placements.count)")
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
            }
        } else {
            prettyPairs(responseLine)
        }
    }

    private var prettyMessages: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "list.bullet.rectangle")
                    .foregroundStyle(.secondary)
                Text("Message list · \(entry.messages.count)")
                    .font(.callout.weight(.semibold))
            }
            ForEach(entry.messages, id: \.rowID) { ref in
                Button {
                    session.openRead(
                        accountID: ref.accountID,
                        placement: ref.placement,
                        id: ref.id
                    )
                    DetachedWindowHost.shared.showCompanion(session: session)
                } label: {
                    AuditMessageCard(session: session, ref: ref)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("Open in Companion Read")
            }
        }
    }

    private var prettyPlacements: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(entry.placements, id: \.rowID) { ref in
                SourceChip(session: session, accountID: ref.accountID, placement: ref.placement)
            }
        }
    }

    @ViewBuilder
    private func prettyPairs(_ text: String) -> some View {
        let pairs = AccessLogFormat.pairs(text)
        if pairs.isEmpty {
            Text(text)
                .font(.callout.monospaced())
                .textSelection(.enabled)
        } else {
            VStack(alignment: .leading, spacing: 4) {
                ForEach(Array(pairs.enumerated()), id: \.offset) { _, pair in
                    HStack(alignment: .top, spacing: 8) {
                        Text(AccessLogFormat.prettyKey(pair.0).uppercased())
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(.secondary)
                            .frame(width: 72, alignment: .leading)
                        Text(pair.1)
                            .font(.caption)
                            .textSelection(.enabled)
                    }
                }
            }
        }
    }

    private var listedFields: GrantFields {
        entry.messages.reduce(
            into: GrantFields(
                subject: false,
                from: false,
                to: false,
                date: false,
                body: false,
                attachmentMetadata: false,
                attachmentContent: false
            )
        ) { acc, ref in
            acc.subject = acc.subject || ref.fields.subject
            acc.from = acc.from || ref.fields.from
            acc.to = acc.to || ref.fields.to
            acc.date = acc.date || ref.fields.date
            acc.body = acc.body || ref.fields.body
            acc.attachmentMetadata = acc.attachmentMetadata || ref.fields.attachmentMetadata
            acc.attachmentContent = acc.attachmentContent || ref.fields.attachmentContent
        }
    }

    private var messageListTotal: Int? {
        let prefix = entry.responseSummary.split(separator: " ").first
        guard let prefix, let count = Int(prefix) else { return nil }
        return count
    }

    private var requestLine: String {
        let text = entry.requestSummary.isEmpty ? entry.detail : entry.requestSummary
        return text.isEmpty ? "—" : text
    }

    private var responseLine: String {
        if case .error(let message) = entry.outcome {
            return entry.responseSummary.isEmpty ? message : "\(entry.responseSummary) · \(message)"
        }
        return entry.responseSummary.isEmpty ? "—" : entry.responseSummary
    }

    private var messagesRawText: String {
        AccessLogFormat.json(entry.messages)
    }

    private var placementsRawText: String {
        entry.placements.map { "\($0.accountID)/\($0.placement)" }.joined(separator: "\n")
    }

    private var timingLabel: String {
        let start = entry.at.formatted(date: .abbreviated, time: .standard)
        let duration = durationLabel
        guard let finishedAt = entry.finishedAt else {
            return "\(start) · \(duration)"
        }
        let sameDay = Calendar.current.isDate(entry.at, inSameDayAs: finishedAt)
        let end = finishedAt.formatted(date: sameDay ? .omitted : .abbreviated, time: .standard)
        return "\(start) → \(end) · \(duration)"
    }

    private var durationLabel: String {
        guard let duration = entry.duration else { return "—" }
        if duration < 1 {
            return String(format: "%.0f ms", duration * 1000)
        }
        return String(format: "%.2f s", duration)
    }
}

private struct AuditMessageCard: View {
    let session: CompanionSession
    let ref: AuditMessageRef

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            previewRow("Subject", ref.subject, ref.fields.subject, empty: "(no subject)")
            if ref.fields.from {
                AddressLine(label: "From", raw: ref.from)
            } else {
                previewRow("From", ref.from, false)
            }
            if ref.fields.to {
                AddressLine(label: "To", raw: ref.to)
            } else {
                previewRow("To", ref.to, false)
            }
            previewRow("Date & Time", ref.date, ref.fields.date)
            SourceChip(session: session, accountID: ref.accountID, placement: ref.placement)
            Text("Body")
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(.secondary)
            bodyPreview
            HStack(spacing: 6) {
                attachmentTile(
                    title: "Attachment names",
                    granted: ref.fields.attachmentMetadata
                )
                attachmentTile(
                    title: "Attachment content",
                    granted: ref.fields.attachmentContent
                )
            }
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 10).strokeBorder(Color.secondary.opacity(0.2)))
    }

    private var bodyPreview: some View {
        Group {
            switch ref.bodyAccess {
            case .granted:
                Text(ref.bodySnippet)
                    .font(.caption)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(8)
                    .background(Color.secondary.opacity(0.06))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
            case .notAvailable:
                Text("not available")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .italic()
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(8)
                    .background(Color.secondary.opacity(0.06))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
            case .notGranted:
                HatchDeniedLabel(placeholder: "Body / snippet")
            }
        }
    }

    private func previewRow(_ label: String, _ value: String, _ granted: Bool, empty: String = " ") -> some View {
        HStack(alignment: .top, spacing: 8) {
            Text(label.uppercased())
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(.secondary)
                .frame(width: 72, alignment: .leading)
            if granted {
                Text(value.isEmpty ? empty : value)
                    .font(.caption)
                    .foregroundStyle(value.isEmpty ? .secondary : .primary)
                    .textSelection(.enabled)
            } else {
                HatchDeniedLabel(placeholder: value.isEmpty ? empty : value)
            }
        }
    }

    private func attachmentTile(title: String, granted: Bool) -> some View {
        HStack(alignment: .center, spacing: 6) {
            Image(systemName: "paperclip")
                .font(.caption)
                .foregroundStyle(.secondary)
            Group {
                if granted {
                    Text("\(title) · none in this response")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                } else {
                    HatchDeniedLabel(fixedHeight: 18)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(6)
        .frame(maxWidth: .infinity, minHeight: 32, alignment: .leading)
        .background(Color.secondary.opacity(0.05))
        .cornerRadius(6)
    }
}

enum AccessLogFormat {
    static func bytes(_ count: Int) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        formatter.includesActualByteCount = true
        formatter.allowedUnits = [.useBytes, .useKB, .useMB, .useGB]
        return formatter.string(fromByteCount: Int64(count))
    }

    static func pairs(_ text: String) -> [(String, String)] {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed != "—" else { return [] }
        guard trimmed.contains("=") else { return [("value", trimmed)] }
        guard let regex = try? NSRegularExpression(
            pattern: #"([A-Za-z_][A-Za-z0-9_]*)=(.*?)(?=\s+[A-Za-z_][A-Za-z0-9_]*=|$)"#
        ) else { return [("value", trimmed)] }
        let ns = trimmed as NSString
        let matches = regex.matches(in: trimmed, range: NSRange(location: 0, length: ns.length))
        return matches.map { match in
            (
                ns.substring(with: match.range(at: 1)),
                ns.substring(with: match.range(at: 2)).trimmingCharacters(in: .whitespaces)
            )
        }
    }

    static func prettyKey(_ key: String) -> String {
        switch key {
        case "q": "Query"
        case "limit": "Limit"
        case "cursor": "Cursor"
        case "account": "Account"
        case "placement": "Placement"
        case "draftID": "Draft"
        case "chars": "Characters"
        case "bodyAccess": "Body"
        case "indexed": "Indexed"
        case "lastIngest": "Last ingest"
        case "source": "Source"
        case "new": "New"
        case "value": "Value"
        default: key
        }
    }

    static func json<T: Encodable>(_ value: T) -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        guard
            let data = try? encoder.encode(value),
            let text = String(data: data, encoding: .utf8)
        else { return "—" }
        return text
    }
}
