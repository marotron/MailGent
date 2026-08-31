import MailStore
import SwiftUI

struct AccessLogView: View {
    @Bindable var session: CompanionSession
    var initialSelection: String?

    @State private var selectedID: String?
    @State private var agentFilter = AgentFilter.all
    @State private var kindFilter = KindFilter.all
    @State private var timeFilter = TimeFilter.all
    @State private var wordQuery = ""

    var body: some View {
        VStack(spacing: 0) {
            filterBar
            if isLargeStore {
                largeStoreBanner
            }
            Divider()
            HSplitView {
                logList
                    .frame(minWidth: 280, idealWidth: 320, maxHeight: .infinity)
                detailPane
                    .frame(minWidth: 360, maxHeight: .infinity)
            }
        }
        .frame(minWidth: 860, minHeight: 420)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear(perform: applyInitialSelection)
        .onChange(of: session.agents.auditRevision) { _, _ in reconcileSelection() }
        .onChange(of: agentFilter) { _, _ in reconcileSelection() }
        .onChange(of: kindFilter) { _, _ in reconcileSelection() }
        .onChange(of: timeFilter) { _, _ in reconcileSelection() }
        .onChange(of: wordQuery) { _, _ in reconcileSelection() }
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

    private var presentKinds: [AuditKind] {
        Array(Set(entries.map(\.kind))).sorted { $0.badgeTitle < $1.badgeTitle }
    }

    private var filtered: [AuditEntry] {
        let now = Date()
        return entries.filter { entry in
            agentFilter.matches(entry.agentName)
                && kindFilter.matches(entry.kind)
                && timeFilter.contains(entry.at, now: now)
                && AccessLogFormat.matchesWords(
                    wordQuery,
                    in: AccessLogFormat.searchTexts(entry)
                )
        }
    }

    private var selectedEntry: AuditEntry? {
        filtered.first { $0.id == selectedID }
    }

    private var isLargeStore: Bool {
        AccessLogFormat.isLargeStore(count: storedCount, bytes: storedBytes)
    }

    private var filterBar: some View {
        HStack(spacing: 10) {
            Picker("Agent", selection: $agentFilter) {
                Text("All agents").tag(AgentFilter.all)
                ForEach(agentNames, id: \.self) { name in
                    Text(name).tag(AgentFilter.named(name))
                }
            }
            .frame(maxWidth: 160)

            Picker("Type", selection: $kindFilter) {
                Text("All types").tag(KindFilter.all)
                ForEach(presentKinds, id: \.self) { kind in
                    Text(kind.badgeTitle).tag(KindFilter.kind(kind))
                }
            }
            .frame(maxWidth: 140)

            Picker("Time", selection: $timeFilter) {
                ForEach(TimeFilter.allCases) { filter in
                    Text(filter.title).tag(filter)
                }
            }
            .frame(maxWidth: 140)

            TextField("Request or response", text: $wordQuery)
                .textFieldStyle(.roundedBorder)
                .frame(minWidth: 140, maxWidth: 240)
                .help("Match words in request or response. All words must match.")

            Spacer(minLength: 8)

            Text(countLabel)
                .font(.caption)
                .foregroundStyle(isLargeStore ? Color.orange : Color.secondary)
                .help("Full stored log: \(storedCount) entries, \(storedBytesLabel)")
        }
        .controlSize(.small)
        .pickerStyle(.menu)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    private var largeStoreBanner: some View {
        Button {
            DetachedWindowHost.shared.showSettings(session: session)
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                Text("Stored log is large — \(storedCount) entries, \(storedBytesLabel). Delete entries in Settings.")
                    .font(.caption)
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.orange.opacity(0.12))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("Open Settings to delete access logs.")
        .accessibilityLabel("Large log. Open Settings to delete entries.")
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
                            : "Try another agent, type, time range, or search."
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
                description: Text("Pick a row to inspect request and response.")
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
        if case .kind(let kind) = kindFilter, !presentKinds.contains(kind) {
            kindFilter = .all
            return
        }
        if let selectedID, filtered.contains(where: { $0.id == selectedID }) { return }
        self.selectedID = filtered.first?.id
    }

    private enum KindFilter: Hashable {
        case all
        case kind(AuditKind)

        func matches(_ kind: AuditKind) -> Bool {
            switch self {
            case .all: true
            case .kind(let expected): kind == expected
            }
        }
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
        HStack(alignment: .center, spacing: 6) {
            AuditOutcomeIcon(outcome: entry.outcome)
                .imageScale(.small)
            AuditKindBadge(kind: entry.kind, compact: true)
                .fixedSize()
            AgentGlyph(name: entry.agentName, size: 13)
            if !requestValue.isEmpty {
                Text(requestValue)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Text("→")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.tertiary)
                .layoutPriority(1)
            Text(responseShort)
                .font(.caption)
                .foregroundStyle(responseStyle)
                .lineLimit(1)
                .layoutPriority(1)
            Spacer(minLength: 8)
            if leakHitCount > 0 {
                AccessLogLeakHitBadge(count: leakHitCount)
            }
            Text(timeLabel)
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .layoutPriority(1)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityText)
    }

    private var leakHitCount: Int {
        AccessLogFormat.leakDetectionCount(for: entry)
    }

    private var requestValue: String {
        if !entry.detail.isEmpty { return entry.detail }
        return entry.requestSummary
    }

    private var responseShort: String {
        switch entry.outcome {
        case .ok:
            let summary = entry.responseSummary.trimmingCharacters(in: .whitespacesAndNewlines)
            if summary.isEmpty { return "ok" }
            return AccessLogFormat.compactResponse(summary)
        case .error(let message):
            if !message.isEmpty { return message }
            return entry.responseSummary.isEmpty ? "error" : AccessLogFormat.compactResponse(entry.responseSummary)
        }
    }

    private var responseStyle: Color {
        switch entry.outcome {
        case .ok: .secondary
        case .error: .orange
        }
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
        var text = "\(entry.kind.badgeTitle) \(entry.agentName) \(requestValue) \(responseShort) \(status)"
        if leakHitCount > 0 {
            text += ". Leak guard \(leakHitCount) detection\(leakHitCount == 1 ? "" : "s")"
        }
        return text
    }
}

private struct AccessLogDetail: View {
    @Bindable var session: CompanionSession
    let entry: AuditEntry

    @State private var requestRaw = false
    @State private var responseRaw = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                header
                togglableField("Request", raw: requestLine, showRaw: $requestRaw) {
                    payloadView(requestLine)
                }
                togglableField("Response", raw: responseRawText, showRaw: $responseRaw) {
                    prettyResponse
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .onChange(of: entry.id) { _, _ in
            requestRaw = false
            responseRaw = false
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .center, spacing: 8) {
                AgentGlyph(name: entry.agentName, size: 18)
                Text(entry.agentName)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                AuditKindBadge(kind: entry.kind)
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
        let hideEmptyPretty = AccessLogFormat.jsonPairs(raw)?.isEmpty == true
        return VStack(alignment: .leading, spacing: 6) {
            RawPrettyHeader(title: title, showRaw: showRaw)
            if showRaw.wrappedValue {
                payloadBox {
                    Text(raw)
                        .font(.callout.monospaced())
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            } else if !hideEmptyPretty {
                payloadBox {
                    pretty()
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
    }

    private func payloadBox<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        content()
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .background(.background, in: RoundedRectangle(cornerRadius: 8))
            .overlay {
                RoundedRectangle(cornerRadius: 8).stroke(.separator)
            }
    }

    @ViewBuilder
    private var prettyResponse: some View {
        if isMessageResponse {
            prettyMessageList
        } else if !entry.placements.isEmpty {
            prettyPlacements
        } else {
            payloadView(responseLine)
        }
    }

    @ViewBuilder
    private func payloadView(_ text: String) -> some View {
        if let pairs = AccessLogFormat.jsonPairs(text) {
            prettyPairList(pairs)
        } else if AccessLogFormat.isJSON(text) {
            Text(AccessLogFormat.prettyJSON(text))
                .font(.callout.monospaced())
                .textSelection(.enabled)
        } else {
            prettyPairs(text)
        }
    }

    private var prettyMessageList: some View {
        VStack(alignment: .leading, spacing: 10) {
            if showsMessageListChrome {
                HStack(spacing: 8) {
                    Image(systemName: "list.bullet.rectangle")
                        .foregroundStyle(.secondary)
                    Text("Message list · \(entry.messages.count)")
                        .font(.callout.weight(.semibold))
                    if let total = messageListTotal, total != entry.messages.count {
                        Text("of \(total)")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                    if hasMorePages {
                        Text("more")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                            .help("Pass nextCursor as cursor to fetch the next page.")
                    }
                }
                if let note = headersOnlyNote {
                    Text(note)
                        .font(.system(size: 10))
                        .foregroundStyle(HeadersOnlyStyle.text)
                }
            }
            if !entry.messages.isEmpty {
                LockedFieldsLegend()
            }
            if AccessLogFormat.showsSanitizedLegend(for: displayMessages) {
                SanitizedFieldsLegend()
            }
            ForEach(displayMessages, id: \.rowID) { ref in
                CollapsibleAuditMessage(
                    session: session,
                    ref: ref,
                    omitsBody: omitsBody,
                    startsExpanded: displayMessages.count == 1
                )
            }
        }
        .id(entry.id)
    }

    private var showsMessageListChrome: Bool {
        switch entry.kind {
        case .search, .list, .listNew: true
        default: false
        }
    }

    private var hasMorePages: Bool {
        AccessLogFormat.jsonString(entry.responseSummary, key: "nextCursor") != nil
    }

    private var omitsBody: Bool {
        switch entry.kind {
        case .search, .list, .listNew: true
        default: false
        }
    }

    private var headersOnlyNote: String? {
        switch entry.kind {
        case .search:
            return "Headers only. Search does not include body — use get."
        case .list:
            return "Headers only. List does not include body — use get."
        case .listNew:
            return "Headers only. New messages do not include body — use get."
        default:
            return nil
        }
    }

    private var prettyPlacements: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Image(systemName: "folder")
                    .foregroundStyle(.secondary)
                Text("Placement list · \(entry.placements.count)")
                    .font(.callout.weight(.semibold))
            }
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
            prettyPairList(pairs)
        }
    }

    @ViewBuilder
    private func prettyPairList(_ pairs: [(String, String)]) -> some View {
        if !pairs.isEmpty {
            let leakGuard = AccessLogFormat.leakGuardDetail(from: entry.responseSummary)
            VStack(alignment: .leading, spacing: 4) {
                ForEach(Array(pairs.enumerated()), id: \.offset) { _, pair in
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text("\(AccessLogFormat.prettyKey(pair.0)):")
                            .font(.callout.monospaced())
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: true, vertical: false)
                        AccessLogJSONValueView(
                            key: pair.0,
                            value: pair.1,
                            accountLabel: session.accountLabel,
                            leakGuard: leakGuard
                        )
                    }
                }
            }
        }
    }

    private var displayMessages: [AuditMessageRef] {
        AccessLogFormat.displayMessages(for: entry)
    }

    private var isMessageResponse: Bool {
        if !displayMessages.isEmpty { return true }
        switch entry.kind {
        case .search, .list, .listNew:
            if case .ok = entry.outcome { return true }
            return false
        default:
            return false
        }
    }

    private var messageListTotal: Int? {
        if let count = AccessLogFormat.jsonInt(entry.responseSummary, key: "count") {
            return count
        }
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

    private var responseRawText: String {
        rawWithError(responseLine)
    }

    private func rawWithError(_ payload: String) -> String {
        if case .error(let message) = entry.outcome, !message.isEmpty {
            return "\(message)\n\n\(payload)"
        }
        return payload
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

private struct CollapsibleAuditMessage: View {
    let session: CompanionSession
    let ref: AuditMessageRef
    let omitsBody: Bool

    @State private var expanded: Bool

    init(
        session: CompanionSession,
        ref: AuditMessageRef,
        omitsBody: Bool,
        startsExpanded: Bool = false
    ) {
        self.session = session
        self.ref = ref
        self.omitsBody = omitsBody
        _expanded = State(initialValue: startsExpanded)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Button(action: toggleExpanded) {
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .rotationEffect(.degrees(expanded ? 90 : 0))
                        .padding(.top, 2)
                        .frame(width: 10)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(collapsedTitle)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.primary)
                            .lineLimit(1)
                        HStack(alignment: .center, spacing: 6) {
                            Text(collapsedMeta)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                            GrantFieldBadgeRow(
                                fields: ref.fields,
                                labelMode: expanded ? .short : .icon
                            )
                            .fixedSize(horizontal: true, vertical: false)
                            if ref.leakDetectionCount > 0 {
                                AccessLogLeakHitBadge(count: ref.leakDetectionCount)
                            }
                        }
                    }
                    Spacer(minLength: 0)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(expanded ? "Collapse message" : "Expand message")
            .accessibilityValue("\(collapsedTitle), \(collapsedMeta)")

            if expanded {
                VStack(alignment: .leading, spacing: 8) {
                    if !ref.displayLeakDetections.isEmpty {
                        LeakGuardDetectionsList(detections: ref.displayLeakDetections)
                    }
                    Button {
                        session.openRead(
                            accountID: ref.accountID,
                            placement: ref.placement,
                            id: ref.id
                        )
                        DetachedWindowHost.shared.showCompanion(session: session)
                    } label: {
                        MessageAccessCard(
                            session: session,
                            ref: ref,
                            omitsBody: omitsBody,
                            showsFieldBadges: false
                        )
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .help("Open in Companion Read")
                }
                .padding(.leading, 18)
            }
        }
    }

    private func toggleExpanded() {
        withAnimation(.easeInOut(duration: 0.15)) {
            expanded.toggle()
        }
    }

    private var collapsedTitle: String {
        if ref.fields.subject {
            return ref.subject.isEmpty ? "(no subject)" : ref.subject
        }
        return ref.id
    }

    private var collapsedMeta: String {
        var parts: [String] = []
        if ref.fields.date, let date = AccessLogFormat.compactMailDate(ref.date) {
            parts.append(date)
        }
        parts.append(session.accountLabel(ref.accountID))
        return parts.joined(separator: " · ")
    }
}

enum AccessLogFormat {
    static func searchTexts(_ entry: AuditEntry) -> [String] {
        var texts = [entry.detail, entry.requestSummary, entry.responseSummary]
        if case .error(let message) = entry.outcome {
            texts.append(message)
        }
        return texts
    }

    static func matchesWords(_ query: String, in texts: [String]) -> Bool {
        let words = query.split { $0.isWhitespace || $0.isNewline }.map(String.init)
        guard !words.isEmpty else { return true }
        return words.allSatisfy { word in
            texts.contains { $0.localizedStandardContains(word) }
        }
    }

    static let largeStoredCount = 1_000
    static let largeStoredBytes = 1_048_576

    static func isLargeStore(count: Int, bytes: Int) -> Bool {
        count >= largeStoredCount || bytes >= largeStoredBytes
    }

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
        case "accountID", "account": "Account"
        case "placement": "Placement"
        case "draftID": "Draft"
        case "chars": "Characters"
        case "bodyAccess": "Body"
        case "subjectAccess": "Subject access"
        case "subjectAccessReason": "Subject reason"
        case "bodyAccessReason": "Body reason"
        case "sanitizedRules": "Sanitized rules"
        case "cc": "Cc"
        case "indexed": "Indexed"
        case "lastIngest": "Last ingest"
        case "source": "Source"
        case "new": "New"
        case "value": "Value"
        default: key
        }
    }

    static func displayValue(
        _ key: String,
        _ value: String,
        accountLabel: (String) -> String
    ) -> String {
        switch key {
        case "accountID", "account":
            let name = accountLabel(value)
            return name.isEmpty ? value : name
        case "newestMessageDate", "lastIngestAt":
            return compactMailDate(value) ?? value
        default:
            return value
        }
    }

    static func compactMailDate(_ raw: String) -> String? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        guard let date = parseMailDate(trimmed) else { return trimmed }
        return date.formatted(date: .abbreviated, time: .shortened)
    }

    private static func parseMailDate(_ raw: String) -> Date? {
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = iso.date(from: raw) { return date }
        iso.formatOptions = [.withInternetDateTime]
        if let date = iso.date(from: raw) { return date }
        let rfc = DateFormatter()
        rfc.locale = Locale(identifier: "en_US_POSIX")
        rfc.dateFormat = "EEE, d MMM yyyy HH:mm:ss Z"
        if let date = rfc.date(from: raw) { return date }
        rfc.dateFormat = "d MMM yyyy HH:mm:ss Z"
        return rfc.date(from: raw)
    }

    static func isJSON(_ text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasPrefix("{") || trimmed.hasPrefix("[") else { return false }
        guard let data = trimmed.data(using: .utf8) else { return false }
        return (try? JSONSerialization.jsonObject(with: data)) != nil
    }

    static func prettyJSON(_ text: String) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let data = trimmed.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data),
              let pretty = try? JSONSerialization.data(
                withJSONObject: obj,
                options: [.prettyPrinted, .sortedKeys]
              ),
              let rendered = String(data: pretty, encoding: .utf8)
        else { return text }
        return rendered
    }

    static func jsonObject(_ text: String) -> [String: Any]? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let data = trimmed.data(using: .utf8) else { return nil }
        return (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
    }

    static func jsonPairs(_ text: String) -> [(String, String)]? {
        guard let obj = jsonObject(text) else { return nil }
        return obj.keys.sorted().map { key in
            (key, jsonValueString(obj[key]))
        }
    }

    private static func jsonValueString(_ any: Any?) -> String {
        guard let any else { return "null" }
        switch any {
        case let s as String:
            return s
        case let n as NSNumber:
            if CFGetTypeID(n) == CFBooleanGetTypeID() {
                return n.boolValue ? "true" : "false"
            }
            return n.stringValue
        case is NSNull:
            return "null"
        default:
            guard JSONSerialization.isValidJSONObject(any),
                  let data = try? JSONSerialization.data(withJSONObject: any, options: [.sortedKeys]),
                  let rendered = String(data: data, encoding: .utf8)
            else { return String(describing: any) }
            return rendered
        }
    }

    static func jsonInt(_ text: String, key: String) -> Int? {
        intValue(jsonObject(text)?[key])
    }

    static func jsonString(_ text: String, key: String) -> String? {
        jsonObject(text)?[key] as? String
    }

    static func compactResponse(_ text: String) -> String {
        guard let obj = jsonObject(text) else { return text }
        if let indexed = intValue(obj["indexedCount"]) {
            var parts: [String] = []
            if let newCount = intValue(obj["newCount"]) {
                parts.append("new=\(newCount)")
            }
            if let removedCount = intValue(obj["removedCount"]) {
                parts.append("removed=\(removedCount)")
            }
            parts.append("indexed=\(indexed)")
            if let last = obj["lastIngestAt"] as? String {
                parts.append("lastIngestAt=\(last)")
            }
            return parts.joined(separator: " ")
        }
        if let count = intValue(obj["count"]) {
            return "\(count) messages"
        }
        if let placements = obj["placements"] as? [Any] {
            return "\(placements.count) placements"
        }
        if let bodyAccess = obj["bodyAccess"] as? String {
            return "bodyAccess=\(bodyAccess)"
        }
        if let draftID = obj["draftID"] as? String {
            if let label = obj["label"] as? String, !label.isEmpty {
                return "draftID=\(draftID) \(label)"
            }
            return "draftID=\(draftID)"
        }
        if let source = obj["source"] as? String {
            return "source=\(source)"
        }
        if let error = obj["error"] as? String {
            return error
        }
        return text
    }

    private static func intValue(_ any: Any?) -> Int? {
        switch any {
        case let n as Int: n
        case let n as NSNumber: n.intValue
        default: nil
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

    static func displayMessages(for entry: AuditEntry) -> [AuditMessageRef] {
        switch entry.kind {
        case .get:
            if entry.messages.isEmpty {
                if let ref = messageRef(from: entry.responseSummary) {
                    return [ref]
                }
                return []
            }
            return entry.messages.map { enrichGetRef($0, from: entry.responseSummary) }
        default:
            return entry.messages
        }
    }

    static func showsSanitizedLegend(for refs: [AuditMessageRef]) -> Bool {
        refs.contains { ref in
            ref.subjectAccess == .sanitized
                || ref.subjectAccess == .withheldConfidential
                || ref.bodyAccess == .sanitized
                || ref.bodyAccess == .withheldConfidential
                || ref.stealth == true
                || !(ref.leakDetections ?? []).isEmpty
        }
    }

    static func leakDetectionCount(for entry: AuditEntry) -> Int {
        let fromMessages = displayMessages(for: entry).reduce(0) { $0 + $1.leakDetectionCount }
        if fromMessages > 0 { return fromMessages }
        if let detail = leakGuardDetail(from: entry.responseSummary) {
            if let rules = detail.sanitizedRules, !rules.isEmpty {
                return rules.count
            }
            if detail.stealth
                || detail.subjectAccess == .sanitized
                || detail.subjectAccess == .withheldConfidential
                || detail.bodyAccess == .sanitized
                || detail.bodyAccess == .withheldConfidential
            {
                return 1
            }
        }
        return 0
    }

    static func messageRef(from responseSummary: String) -> AuditMessageRef? {
        guard let obj = jsonObject(responseSummary),
              let id = obj["id"] as? String,
              let accountID = obj["accountID"] as? String,
              let placement = obj["placement"] as? String
        else { return nil }

        let subject = obj["subject"] as? String ?? ""
        let from = obj["from"] as? String ?? ""
        let to = obj["to"] as? String ?? ""
        let cc = obj["cc"] as? String ?? ""
        let date = obj["date"] as? String ?? ""
        let body = obj["body"] as? String ?? ""
        let subjectAccess = auditAccess(obj["subjectAccess"])
        let bodyAccess = auditAccess(obj["bodyAccess"]) ?? (body.isEmpty ? .notAvailable : .granted)
        let rules = sanitizedRules(from: obj["sanitizedRules"])
        let stealth = (obj["note"] as? String)?.contains("substituted") == true
        let fields = inferredGrantFields(from: obj)
        let attachments = parseAttachments(from: obj)

        return AuditMessageRef(
            accountID: accountID,
            placement: placement,
            id: id,
            subject: subject,
            from: from,
            date: date,
            to: to,
            cc: cc,
            bodySnippet: String(body.prefix(AuditMessageRef.bodySnippetCap)),
            subjectAccess: subjectAccess,
            bodyAccess: bodyAccess,
            sanitizedRules: rules,
            stealth: stealth ? true : nil,
            fields: fields,
            attachments: attachments
        )
    }

    static func enrichGetRef(_ ref: AuditMessageRef, from responseSummary: String) -> AuditMessageRef {
        guard let obj = jsonObject(responseSummary) else { return ref }
        let parsedSubjectAccess = auditAccess(obj["subjectAccess"])
        let parsedBodyAccess = auditAccess(obj["bodyAccess"])
        let parsedRules = sanitizedRules(from: obj["sanitizedRules"])
        let parsedStealth = (obj["note"] as? String)?.contains("substituted") == true

        let mergedRules: [String]?
        if let existing = ref.sanitizedRules, !existing.isEmpty {
            mergedRules = existing
        } else {
            mergedRules = parsedRules
        }

        let mergedStealth: Bool?
        if ref.stealth == true || parsedStealth {
            mergedStealth = true
        } else {
            mergedStealth = ref.stealth
        }

        guard parsedSubjectAccess != nil
            || parsedBodyAccess != nil
            || mergedRules != nil
            || mergedStealth == true
        else { return ref }

        return AuditMessageRef(
            accountID: ref.accountID,
            placement: ref.placement,
            id: ref.id,
            subject: ref.subject,
            from: ref.from,
            date: ref.date,
            to: ref.to,
            cc: ref.cc,
            bodySnippet: ref.bodySnippet,
            subjectAccess: ref.subjectAccess ?? parsedSubjectAccess,
            bodyAccess: parsedBodyAccess ?? ref.bodyAccess,
            subjectOriginal: ref.subjectOriginal,
            bodyOriginal: ref.bodyOriginal,
            sanitizedRules: mergedRules,
            stealth: mergedStealth,
            leakDetections: ref.leakDetections,
            fields: ref.fields,
            attachments: ref.attachments
        )
    }

    static func leakGuardDetail(from responseSummary: String) -> LeakGuardResponseDetail? {
        guard let obj = jsonObject(responseSummary) else { return nil }
        let subjectAccess = auditAccess(obj["subjectAccess"])
        let bodyAccess = auditAccess(obj["bodyAccess"])
        let rules = sanitizedRules(from: obj["sanitizedRules"])
        let stealth = (obj["note"] as? String)?.contains("substituted") == true
        guard subjectAccess != nil || bodyAccess != nil || rules != nil || stealth else { return nil }
        return LeakGuardResponseDetail(
            subjectAccess: subjectAccess,
            bodyAccess: bodyAccess,
            sanitizedRules: rules,
            stealth: stealth,
            subject: obj["subject"] as? String,
            body: obj["body"] as? String
        )
    }

    private static func auditAccess(_ any: Any?) -> AuditBodyAccess? {
        guard let raw = any as? String else { return nil }
        return AuditBodyAccess(rawValue: raw)
    }

    private static func sanitizedRules(from any: Any?) -> [String]? {
        guard let rules = any as? [Any] else { return nil }
        let labels = rules.compactMap { $0 as? String }.filter { !$0.isEmpty }
        return labels.isEmpty ? nil : labels
    }

    private static func inferredGrantFields(from obj: [String: Any]) -> GrantFields {
        GrantFields(
            subject: obj["subjectAccess"] as? String != AuditBodyAccess.notGranted.rawValue,
            from: (obj["from"] as? String)?.isEmpty == false,
            to: (obj["to"] as? String)?.isEmpty == false,
            cc: (obj["cc"] as? String)?.isEmpty == false,
            date: (obj["date"] as? String)?.isEmpty == false,
            body: obj["bodyAccess"] as? String != AuditBodyAccess.notGranted.rawValue,
            attachmentMetadata: obj["attachmentAccess"] as? String == "granted",
            attachmentContent: false
        )
    }

    private static func parseAttachments(from obj: [String: Any]) -> [MailAttachment] {
        guard let items = obj["attachments"] as? [[String: Any]] else { return [] }
        return items.compactMap { item in
            guard let filename = item["filename"] as? String else { return nil }
            let byteCount = intValue(item["byteCount"]) ?? 0
            return MailAttachment(filename: filename, byteCount: byteCount)
        }
    }
}

struct LeakGuardResponseDetail: Equatable {
    let subjectAccess: AuditBodyAccess?
    let bodyAccess: AuditBodyAccess?
    let sanitizedRules: [String]?
    let stealth: Bool
    let subject: String?
    let body: String?
}

private struct AccessLogJSONValueView: View {
    let key: String
    let value: String
    let accountLabel: (String) -> String
    var leakGuard: LeakGuardResponseDetail?

    var body: some View {
        Group {
            switch key {
            case "subject":
                fieldValue(
                    text: value,
                    access: leakGuard?.subjectAccess,
                    original: nil
                )
            case "body":
                fieldValue(
                    text: value,
                    access: leakGuard?.bodyAccess,
                    original: nil
                )
            case "subjectAccess", "bodyAccess":
                accessBadge(value)
            default:
                Text(AccessLogFormat.displayValue(key, value, accountLabel: accountLabel))
                    .font(.callout.monospaced())
                    .textSelection(.enabled)
            }
        }
    }

    @ViewBuilder
    private func fieldValue(
        text: String,
        access: AuditBodyAccess?,
        original: String?
    ) -> some View {
        if let access {
            switch access {
            case .sanitized:
                SanitizedFieldText(
                    text: text,
                    original: original,
                    rules: leakGuard?.sanitizedRules,
                    stealth: leakGuard?.stealth == true,
                    font: .callout.monospaced()
                )
            case .withheldConfidential:
                WithheldLabel(original: original, rules: leakGuard?.sanitizedRules)
            default:
                Text(AccessLogFormat.displayValue(key, text, accountLabel: accountLabel))
                    .font(.callout.monospaced())
                    .textSelection(.enabled)
            }
        } else {
            Text(AccessLogFormat.displayValue(key, text, accountLabel: accountLabel))
                .font(.callout.monospaced())
                .textSelection(.enabled)
        }
    }

    @ViewBuilder
    private func accessBadge(_ raw: String) -> some View {
        if let access = AuditBodyAccess(rawValue: raw) {
            switch access {
            case .sanitized, .withheldConfidential:
                Text(raw)
                    .font(.callout.monospaced())
                    .foregroundStyle(SanitizedFieldStyle.legend)
            default:
                Text(raw)
                    .font(.callout.monospaced())
                    .textSelection(.enabled)
            }
        } else {
            Text(raw)
                .font(.callout.monospaced())
                .textSelection(.enabled)
        }
    }
}
