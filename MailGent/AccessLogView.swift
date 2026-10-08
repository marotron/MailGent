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
            AuditOutcomeIcon(
                outcome: entry.outcome,
                emptySuccess: AccessLogFormat.isEmptySuccess(entry)
            )
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
                AccessLogLeakHitBadge(count: leakHitCount, compact: true)
            }
            if passHitCount > 0 {
                AccessLogRuleHitBadge(polarity: .pass, count: passHitCount)
            }
            if blockHitCount > 0 {
                AccessLogRuleHitBadge(polarity: .block, count: blockHitCount)
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

    private var passHitCount: Int {
        AccessLogFormat.passApplicationCount(for: entry)
    }

    private var blockHitCount: Int {
        AccessLogFormat.blockApplicationCount(for: entry)
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
        if passHitCount > 0 {
            text += passHitCount == 1
                ? ". Pass applied"
                : ". Pass applied, \(passHitCount) hits"
        }
        if blockHitCount > 0 {
            text += blockHitCount == 1
                ? ". Block applied"
                : ". Block applied, \(blockHitCount) hits"
        }
        return text
    }
}

/// Access Log Request/Response JSON pane — compact mono; Pretty is syntax-colored.
private struct AccessLogJSONText: View {
    let raw: String
    let style: AccessLogJSONStyle

    var body: some View {
        Group {
            switch style {
            case .pretty:
                Text(AccessLogFormat.highlightedPrettyJSON(raw))
            case .raw:
                Text(AccessLogFormat.compactJSON(raw))
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.primary)
            }
        }
        .textSelection(.enabled)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct AccessLogDetail: View {
    @Bindable var session: CompanionSession
    let entry: AuditEntry

    @State private var requestView: AccessLogSideView = .formatted
    @State private var requestJSONStyle: AccessLogJSONStyle = .pretty
    @State private var responseView: AccessLogSideView = .formatted
    @State private var responseJSONStyle: AccessLogJSONStyle = .pretty

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                header
                modeField(
                    "Request",
                    raw: requestLine,
                    view: $requestView,
                    jsonStyle: $requestJSONStyle
                ) {
                    formattedRequest
                }
                modeField(
                    "Response",
                    raw: responseRawText,
                    view: $responseView,
                    jsonStyle: $responseJSONStyle
                ) {
                    formattedResponse
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .onChange(of: entry.id) { _, _ in
            requestView = .formatted
            requestJSONStyle = .pretty
            responseView = .formatted
            responseJSONStyle = .pretty
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
        let emptySuccess = AccessLogFormat.isEmptySuccess(entry)
        HStack(spacing: 6) {
            AuditOutcomeIcon(outcome: entry.outcome, emptySuccess: emptySuccess)
            switch entry.outcome {
            case .ok:
                Text("ok")
                    .font(.caption.weight(.semibold).monospaced())
                    .foregroundStyle(emptySuccess ? Color.secondary : Color.green)
            case .error(let message):
                Text(message.isEmpty ? "error" : message)
                    .font(.caption.weight(.semibold).monospaced())
                    .foregroundStyle(.orange)
                    .lineLimit(2)
            }
        }
    }

    private func modeField<Formatted: View>(
        _ title: String,
        raw: String,
        view: Binding<AccessLogSideView>,
        jsonStyle: Binding<AccessLogJSONStyle>,
        @ViewBuilder formatted: () -> Formatted
    ) -> some View {
        return VStack(alignment: .leading, spacing: 6) {
            AccessLogModeHeader(title: title, view: view, jsonStyle: jsonStyle)
            switch view.wrappedValue {
            case .formatted:
                payloadBox {
                    formatted()
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            case .json:
                payloadBox {
                    AccessLogJSONText(raw: raw, style: jsonStyle.wrappedValue)
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
    private var formattedRequest: some View {
        let pairs = AccessLogFormat.jsonPairs(requestLine) ?? AccessLogFormat.pairs(requestLine)
        VStack(alignment: .leading, spacing: 6) {
            Text(AccessLogFormat.requestIntent(for: entry.kind))
                .font(.caption.weight(.semibold))
            if !pairs.isEmpty {
                ForEach(Array(pairs.enumerated()), id: \.offset) { _, pair in
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text("\(AccessLogFormat.prettyKey(pair.0)):")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: true, vertical: false)
                        Text(
                            AccessLogFormat.displayValue(
                                pair.0,
                                pair.1,
                                accountLabel: session.accountLabel
                            )
                        )
                        .font(.caption)
                        .textSelection(.enabled)
                    }
                }
            } else if requestLine != "—" {
                Text(requestLine)
                    .font(.caption.monospaced())
                    .textSelection(.enabled)
            }
        }
    }

    @ViewBuilder
    private var formattedResponse: some View {
        switch entry.kind {
        case .get:
            formattedGetResponse
        case .search, .list, .listNew:
            formattedSearchListResponse
        case .getAttachment:
            formattedAttachmentResponse
        default:
            if !entry.placements.isEmpty {
                prettyPlacements
            } else {
                payloadView(responseLine)
            }
        }
    }

    @ViewBuilder
    private func payloadView(_ text: String) -> some View {
        if let pairs = AccessLogFormat.jsonPairs(text) {
            prettyPairList(pairs)
        } else if AccessLogFormat.isJSON(text) {
            Text(AccessLogFormat.prettyJSON(text))
                .font(.caption.monospaced())
                .textSelection(.enabled)
        } else {
            prettyPairs(text)
        }
    }

    private var formattedGetResponse: some View {
        let refs = displayMessages
        return VStack(alignment: .leading, spacing: 10) {
            kindChrome(title: "Message", systemImage: "envelope")
            if let ref = refs.first {
                messageMetaRow(ref)
                MessageAccessCard(
                    session: session,
                    ref: ref,
                    omitsBody: false,
                    showsFieldBadges: false,
                    attachmentContentCards: AccessLogFormat.getAttachmentContentCards(for: ref),
                    showsChipRowActions: true,
                    onChipRowPreview: {
                        session.openRead(
                            accountID: ref.accountID,
                            placement: ref.placement,
                            id: ref.id
                        )
                        DetachedWindowHost.shared.showCompanion(session: session)
                    }
                )

                if AccessLogFormat.showsSanitizedLegend(for: [ref]) {
                    SanitizedFieldsLegend()
                }
                if AccessLogFormat.hasLockedFields(ref) {
                    LockedFieldsLegend()
                }
            } else {
                payloadView(responseLine)
            }
        }
        .id(entry.id)
    }

    private var formattedSearchListResponse: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "list.bullet.rectangle")
                    .foregroundStyle(.secondary)
                Text("Message list · \(displayMessages.count)")
                    .font(.callout.weight(.semibold))
                if let total = messageListTotal, total != displayMessages.count {
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
            ForEach(displayMessages, id: \.rowID) { ref in
                SearchResultCard(session: session, ref: ref)
            }
        }
        .id(entry.id)
    }

    private var formattedAttachmentResponse: some View {
        let refs = displayMessages
        let model = AccessLogFormat.attachmentContent(for: entry)
        return VStack(alignment: .leading, spacing: 10) {
            kindChrome(title: "Attachment", systemImage: "paperclip")
            if let ref = refs.first {
                HStack(alignment: .center, spacing: 8) {
                    Text("for")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(ref.fields.subject
                         ? (ref.subject.isEmpty ? "(no subject)" : ref.subject)
                         : ref.id)
                        .font(.caption.weight(.semibold))
                        .lineLimit(1)
                    Spacer(minLength: 8)
                    OpenInMailButton(
                        session: session,
                        locator: (ref.accountID, ref.placement, ref.id),
                        title: "Open message in Apple Mail"
                    )
                }
                messageMetaRow(ref)
            }
            if let model {
                FileCard(model: model, showsPreview: true) {
                    if let ref = refs.first {
                        session.openAttachment(
                            accountID: ref.accountID,
                            placement: ref.placement,
                            id: ref.id,
                            filename: model.filename
                        )
                    }
                }
            } else {
                payloadView(responseLine)
            }
        }
        .id(entry.id)
    }

    private func kindChrome(title: String, systemImage: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: systemImage)
                .foregroundStyle(.secondary)
            Text(title)
                .font(.callout.weight(.semibold))
        }
    }

    private func messageMetaRow(_ ref: AuditMessageRef) -> some View {
        HStack(alignment: .center, spacing: 6) {
            Text(collapsedMeta(for: ref))
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            GrantFieldBadgeRow(
                fields: ref.fields,
                labelMode: .short,
                passRevealed: ref.passRevealedFields,
                blockWithheld: ref.blockWithheldFields,
                conditionalConfirmed: ref.conditionalConfirmedFields,
                conditionalBlocked: ref.conditionalUserBlockedFields
            )
            .fixedSize(horizontal: true, vertical: false)
            if ref.leakDetectionCount > 0 {
                AccessLogLeakHitBadge(count: ref.leakDetectionCount)
            }
            Spacer(minLength: 0)
        }
    }

    private func collapsedMeta(for ref: AuditMessageRef) -> String {
        var parts: [String] = []
        if ref.fields.date, let date = AccessLogFormat.compactMailDate(ref.date) {
            parts.append(date)
        }
        parts.append(session.accountLabel(ref.accountID))
        return parts.joined(separator: " · ")
    }

    private var hasMorePages: Bool {
        AccessLogFormat.jsonString(entry.responseSummary, key: "nextCursor") != nil
    }

    private var headersOnlyNote: String? {
        switch entry.kind {
        case .search:
            return "Headers only. Search does not include body — use get. Cards show only fields from the agent response."
        case .list:
            return "Headers only. List does not include body — use get. Cards show only fields from the agent response."
        case .listNew:
            return "Headers only. New messages do not include body — use get. Cards show only fields from the agent response."
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
                .font(.caption)
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
                            .font(.caption)
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
    let attachmentContentDetail: String
    let mailHandoffTitle: String

    @State private var expanded: Bool

    init(
        session: CompanionSession,
        ref: AuditMessageRef,
        omitsBody: Bool,
        attachmentContentDetail: String = "none in this response",
        startsExpanded: Bool = false,
        mailHandoffTitle: String = "Open in Apple Mail"
    ) {
        self.session = session
        self.ref = ref
        self.omitsBody = omitsBody
        self.attachmentContentDetail = attachmentContentDetail
        self.mailHandoffTitle = mailHandoffTitle
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
                    VStack(alignment: .leading, spacing: 4) {
                        Text(collapsedTitle)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.primary)
                            .lineLimit(1)
                        HStack(alignment: .center, spacing: 6) {
                            Text(collapsedMeta)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                            if !expanded {
                                GrantFieldBadgeRow(
                                    fields: ref.fields,
                                    labelMode: .icon,
                                    passRevealed: ref.passRevealedFields,
                                    blockWithheld: ref.blockWithheldFields,
                                    conditionalConfirmed: ref.conditionalConfirmedFields,
                                    conditionalBlocked: ref.conditionalUserBlockedFields
                                )
                                .fixedSize(horizontal: true, vertical: false)
                                if ref.leakDetectionCount > 0 {
                                    AccessLogLeakHitBadge(
                                        count: ref.leakDetectionCount,
                                        compact: true
                                    )
                                }
                            }
                        }
                        if expanded {
                            HStack(alignment: .center, spacing: 6) {
                                GrantFieldBadgeRow(
                                    fields: ref.fields,
                                    labelMode: .short,
                                    passRevealed: ref.passRevealedFields,
                                    blockWithheld: ref.blockWithheldFields,
                                    conditionalConfirmed: ref.conditionalConfirmedFields,
                                    conditionalBlocked: ref.conditionalUserBlockedFields
                                )
                                .fixedSize(horizontal: true, vertical: false)
                                if ref.leakDetectionCount > 0 {
                                    AccessLogLeakHitBadge(count: ref.leakDetectionCount)
                                }
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
                    MessageAccessCard(
                        session: session,
                        ref: ref,
                        omitsBody: omitsBody,
                        showsFieldBadges: false,
                        attachmentContentDetail: attachmentContentDetail
                    )
                    .frame(maxWidth: .infinity, alignment: .leading)

                    OpenInMailButton(
                        session: session,
                        locator: (ref.accountID, ref.placement, ref.id),
                        title: mailHandoffTitle
                    )

                    if AccessLogFormat.showsSanitizedLegend(for: [ref]) {
                        SanitizedFieldsLegend()
                    }
                    if AccessLogFormat.hasLockedFields(ref) {
                        LockedFieldsLegend()
                    }
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
        case "q", "query": "Query"
        case "limit": "Limit"
        case "cursor": "Cursor"
        case "accountID", "account": "Account"
        case "placement": "Placement"
        case "draftID": "Draft"
        case "chars": "Characters"
        case "bodyAccess": "Body"
        case "subjectAccess": "Subject access"
        case "attachmentContentAccess": "Attachment content"
        case "attachmentAccess": "Attachment info"
        case "subjectAccessReason": "Subject reason"
        case "bodyAccessReason": "Body reason"
        case "conditionalAccessFields": "Ask user allowed"
        case "conditionalBlockedFields": "Ask user blocked"
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
        case "subjectAccessReason", "bodyAccessReason":
            switch value {
            case "conditional": return "User allowed"
            case "conditional_blocked": return "User blocked"
            case "leak_guard": return "Leak guard"
            case "grant": return "Grant"
            default: return value
            }
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

    /// Pretty-printed JSON with Access Log syntax colors (keys / strings / numbers / …).
    static func highlightedPrettyJSON(_ text: String) -> AttributedString {
        highlightedJSON(prettyJSON(text))
    }

    /// Lightweight JSON syntax coloring for Pretty mode (matches prototype `colorizeJSON`).
    static func highlightedJSON(_ text: String) -> AttributedString {
        var output = AttributedString()
        var i = text.startIndex
        while i < text.endIndex {
            let ch = text[i]
            if ch == "\"" {
                var j = text.index(after: i)
                var escaped = false
                while j < text.endIndex {
                    let c = text[j]
                    if escaped {
                        escaped = false
                        j = text.index(after: j)
                        continue
                    }
                    if c == "\\" {
                        escaped = true
                        j = text.index(after: j)
                        continue
                    }
                    if c == "\"" {
                        j = text.index(after: j)
                        break
                    }
                    j = text.index(after: j)
                }
                let chunk = text[i..<j]
                let after = text[j...].drop(while: { $0.isWhitespace })
                let isKey = after.first == ":"
                appendJSONRun(String(chunk), kind: isKey ? .key : .string, to: &output)
                i = j
                continue
            }
            if let numberEnd = jsonNumberEndIndex(from: i, in: text) {
                appendJSONRun(String(text[i..<numberEnd]), kind: .number, to: &output)
                i = numberEnd
                continue
            }
            if text[i...].hasPrefix("true") || text[i...].hasPrefix("false") {
                let lit = text[i...].hasPrefix("true") ? "true" : "false"
                let end = text.index(i, offsetBy: lit.count)
                if isJSONLiteralBoundary(before: i, after: end, in: text) {
                    appendJSONRun(lit, kind: .bool, to: &output)
                    i = end
                    continue
                }
            }
            if text[i...].hasPrefix("null") {
                let end = text.index(i, offsetBy: 4)
                if isJSONLiteralBoundary(before: i, after: end, in: text) {
                    appendJSONRun("null", kind: .null, to: &output)
                    i = end
                    continue
                }
            }
            if "{}[],:".contains(ch) {
                appendJSONRun(String(ch), kind: .punctuation, to: &output)
                i = text.index(after: i)
                continue
            }
            appendJSONRun(String(ch), kind: .plain, to: &output)
            i = text.index(after: i)
        }
        return output
    }

    private enum JSONHighlightKind {
        case key, string, number, bool, null, punctuation, plain
    }

    private static let jsonFont = Font.system(size: 11, design: .monospaced)

    private static func appendJSONRun(
        _ text: String,
        kind: JSONHighlightKind,
        to output: inout AttributedString
    ) {
        var run = AttributedString(text)
        run.font = jsonFont
        run.foregroundColor = jsonColor(for: kind)
        if kind == .null {
            run.inlinePresentationIntent = .emphasized
        }
        output.append(run)
    }

    private static func jsonColor(for kind: JSONHighlightKind) -> Color {
        // Prototype `.jx-*` palette (Access Log Pretty JSON).
        switch kind {
        case .key: Color(red: 0.043, green: 0.341, blue: 0.816) // #0b57d0
        case .string: Color(red: 0.039, green: 0.478, blue: 0.243) // #0a7a3e
        case .number: Color(red: 0.647, green: 0.055, blue: 0.055) // #a50e0e
        case .bool: Color(red: 0.541, green: 0.247, blue: 0.988) // #8a3ffc
        case .null, .punctuation: Color(red: 0.373, green: 0.427, blue: 0.525) // #5f6d86
        case .plain: Color.primary
        }
    }

    private static func isJSONLiteralBoundary(before: String.Index, after: String.Index, in text: String) -> Bool {
        let beforeOK: Bool = {
            guard before > text.startIndex else { return true }
            let prev = text[text.index(before: before)]
            return !prev.isLetter && !prev.isNumber && prev != "_"
        }()
        let afterOK: Bool = {
            guard after < text.endIndex else { return true }
            let next = text[after]
            return !next.isLetter && !next.isNumber && next != "_"
        }()
        return beforeOK && afterOK
    }

    /// End index of a JSON number starting at `start`, or nil if not a number.
    private static func jsonNumberEndIndex(from start: String.Index, in text: String) -> String.Index? {
        guard start < text.endIndex else { return nil }
        var j = start
        if text[j] == "-" {
            j = text.index(after: j)
        }
        guard j < text.endIndex, text[j].isNumber else { return nil }
        while j < text.endIndex, text[j].isNumber {
            j = text.index(after: j)
        }
        if j < text.endIndex, text[j] == "." {
            let afterDot = text.index(after: j)
            guard afterDot < text.endIndex, text[afterDot].isNumber else { return j }
            j = afterDot
            while j < text.endIndex, text[j].isNumber {
                j = text.index(after: j)
            }
        }
        if j < text.endIndex, text[j] == "e" || text[j] == "E" {
            var k = text.index(after: j)
            if k < text.endIndex, text[k] == "+" || text[k] == "-" {
                k = text.index(after: k)
            }
            guard k < text.endIndex, text[k].isNumber else { return j }
            j = k
            while j < text.endIndex, text[j].isNumber {
                j = text.index(after: j)
            }
        }
        return j
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
            switch obj["bodyAccessReason"] as? String {
            case "conditional":
                return "bodyAccess=\(bodyAccess) · user allowed"
            case "conditional_blocked":
                return "bodyAccess=\(bodyAccess) · user blocked"
            default:
                return "bodyAccess=\(bodyAccess)"
            }
        }
        if let attachmentAccess = obj["attachmentContentAccess"] as? String {
            if let filename = obj["filename"] as? String, !filename.isEmpty {
                return "attachmentContentAccess=\(attachmentAccess) \(filename)"
            }
            return "attachmentContentAccess=\(attachmentAccess)"
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

    /// Successful search / list / list_new / placements call that returned zero items.
    static func isEmptySuccess(_ entry: AuditEntry) -> Bool {
        guard case .ok = entry.outcome else { return false }
        switch entry.kind {
        case .search, .list, .listNew:
            return resultCount(for: entry) == 0
        case .listPlacements:
            return placementCount(for: entry) == 0
        default:
            return false
        }
    }

    private static func resultCount(for entry: AuditEntry) -> Int? {
        if let count = jsonInt(entry.responseSummary, key: "count") {
            return count
        }
        if let obj = jsonObject(entry.responseSummary),
           let items = obj["items"] as? [Any]
        {
            return items.count
        }
        if !entry.messages.isEmpty {
            return entry.messages.count
        }
        return nil
    }

    private static func placementCount(for entry: AuditEntry) -> Int? {
        if let obj = jsonObject(entry.responseSummary),
           let placements = obj["placements"] as? [Any]
        {
            return placements.count
        }
        return entry.placements.count
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
        case .get, .getAttachment:
            if entry.messages.isEmpty {
                if let ref = messageRef(from: entry.responseSummary) {
                    return [ref]
                }
                return []
            }
            return entry.messages.map { ref in
                let enriched = enrichGetRef(ref, from: entry.responseSummary)
                guard entry.kind == .getAttachment else { return enriched }
                return enrichAttachmentRef(enriched, from: entry.responseSummary)
            }
        default:
            return entry.messages
        }
    }

    /// File-card state for Access Log Formatted Response (`get_attachment` / get Attachment Content).
    enum AttachmentCardState: Equatable, Sendable {
        case granted
        case denied
        case missing
        case huge
    }

    /// Structured attachment outcome feeding `FileCard` (and string helpers).
    struct AttachmentCardModel: Equatable, Sendable {
        var state: AttachmentCardState
        var filename: String
        var byteCount: Int? = nil
        var isPartial: Bool = false
        var note: String? = nil
        var passNick: String? = nil
        /// Short Formatted line under the filename (overrides default state copy).
        var stateLineOverride: String? = nil

        var sizeLabel: String? {
            guard let byteCount else { return nil }
            return MailAttachment(filename: filename, byteCount: byteCount).sizeLabel
        }

        var typeBadge: String {
            let ext = URL(fileURLWithPath: filename).pathExtension.uppercased()
            return ext.isEmpty ? "FILE" : String(ext.prefix(4))
        }

        var typeDescription: String {
            let ext = URL(fileURLWithPath: filename).pathExtension.lowercased()
            switch ext {
            case "pdf": return "PDF document"
            case "png", "jpg", "jpeg", "gif", "webp", "heic": return "Image"
            case "txt", "md", "csv": return "Text"
            case "zip", "gz", "tar": return "Archive"
            case "": return "Attachment"
            default: return "\(ext.uppercased()) file"
            }
        }

        var stateLine: String {
            if let stateLineOverride, !stateLineOverride.isEmpty { return stateLineOverride }
            switch state {
            case .granted: return ""
            case .denied: return "Not allowed by the current grant."
            case .missing: return "Not available in Mail."
            case .huge: return "Too large to deliver."
            }
        }

        var previewBlockedReason: String? {
            switch state {
            case .granted: return nil
            case .denied: return "Attachment content is not granted — Preview stays closed."
            case .missing: return "Attachment is not available in Mail — nothing to preview."
            case .huge: return "Attachment is too large to deliver — Preview stays closed."
            }
        }

        /// Backward-compatible tile / list string.
        var detailString: String {
            switch state {
            case .granted:
                if let sizeLabel { return "\(filename) · \(sizeLabel)" }
                return filename
            case .denied:
                return "not granted"
            case .missing:
                return "not available"
            case .huge:
                if let sizeLabel { return "\(filename) · \(sizeLabel) · too large" }
                return "too large"
            }
        }
    }

    /// Tile copy for Attachment Content. `get_attachment` uses response access; `get` stays "none in this response".
    static func attachmentContentDetail(for entry: AuditEntry) -> String {
        attachmentContent(for: entry)?.detailString ?? "none in this response"
    }

    static func attachmentContent(for entry: AuditEntry) -> AttachmentCardModel? {
        guard entry.kind == .getAttachment,
              let obj = jsonObject(entry.responseSummary),
              let access = obj["attachmentContentAccess"] as? String
        else { return nil }

        let filename = (obj["filename"] as? String).flatMap { $0.isEmpty ? nil : $0 } ?? "attachment"
        let byteCount = intValue(obj["byteCount"])
        let isPartial = obj["isPartial"] as? Bool ?? false
        let note = obj["note"] as? String
        let passNick = attachmentPassNick(from: entry)

        switch access {
        case "granted":
            return AttachmentCardModel(
                state: .granted,
                filename: filename,
                byteCount: byteCount,
                isPartial: isPartial,
                note: note,
                passNick: passNick
            )
        case "not_granted":
            return AttachmentCardModel(
                state: .denied,
                filename: filename,
                byteCount: byteCount,
                isPartial: isPartial,
                note: note
            )
        case "not_available":
            return AttachmentCardModel(
                state: .missing,
                filename: filename,
                byteCount: byteCount,
                isPartial: isPartial,
                note: note
            )
        case "too_large":
            return AttachmentCardModel(
                state: .huge,
                filename: filename,
                byteCount: byteCount,
                isPartial: isPartial,
                note: note
            )
        default:
            return AttachmentCardModel(
                state: .missing,
                filename: filename,
                byteCount: byteCount,
                isPartial: isPartial,
                note: note ?? access
            )
        }
    }

    /// FileCard-shaped Attachment Content inside a `get` Formatted card (no nested Preview).
    static func getAttachmentContentCards(for ref: AuditMessageRef) -> [AttachmentCardModel] {
        let named = ref.attachments
        if !ref.fields.attachmentContent {
            if named.isEmpty {
                return [
                    AttachmentCardModel(state: .denied, filename: "(attachment)")
                ]
            }
            return named.map {
                AttachmentCardModel(state: .denied, filename: $0.filename, byteCount: $0.byteCount)
            }
        }
        let omitted = "Not included in get — use get_attachment."
        if named.isEmpty {
            return [
                AttachmentCardModel(
                    state: .missing,
                    filename: "(none named)",
                    stateLineOverride: omitted
                )
            ]
        }
        return named.map {
            AttachmentCardModel(
                state: .missing,
                filename: $0.filename,
                byteCount: $0.byteCount,
                stateLineOverride: omitted
            )
        }
    }

    private static func attachmentPassNick(from entry: AuditEntry) -> String? {
        for ref in displayMessages(for: entry) {
            if let mark = ref.appliedRuleMark(for: \.attachmentContent), mark.polarity == .pass {
                return mark.nick
            }
        }
        return nil
    }

    static func requestIntent(for kind: AuditKind) -> String {
        switch kind {
        case .get: "Fetch one message."
        case .getAttachment: "Fetch one attachment’s file bytes."
        case .openInMail: "Open a message in Apple Mail."
        case .search: "Search messages."
        case .list: "List messages."
        case .listNew: "List new messages."
        case .listPlacements: "List placements."
        case .status: "Read MailGent status."
        case .updateIndex: "Update the mail index."
        case .setSource: "Set the mail source."
        case .createDraft: "Create a draft."
        case .updateDraft: "Update a draft."
        case .pair: "Pair an agent."
        case .revoke: "Revoke a pairing."
        }
    }

    static func compactJSON(_ text: String) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let data = trimmed.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data),
              JSONSerialization.isValidJSONObject(obj),
              let compact = try? JSONSerialization.data(withJSONObject: obj, options: [.sortedKeys]),
              let rendered = String(data: compact, encoding: .utf8)
        else { return text }
        return rendered
    }

    static func hasLockedFields(_ ref: AuditMessageRef) -> Bool {
        let f = ref.fields
        return !f.subject || !f.from || !f.to || !f.cc || !f.date
            || !f.body || !f.attachmentMetadata || !f.attachmentContent
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

    static func passApplicationCount(for entry: AuditEntry) -> Int {
        displayMessages(for: entry).reduce(0) { $0 + $1.passApplicationCount }
    }

    static func blockApplicationCount(for entry: AuditEntry) -> Int {
        displayMessages(for: entry).reduce(0) { $0 + $1.blockApplicationCount }
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
            attachments: attachments,
            conditionalFields: conditionalFields(from: obj),
            conditionalBlockedFields: conditionalBlockedFields(from: obj),
            isPartial: obj["isPartial"] as? Bool ?? false
        )
    }

    static func enrichGetRef(_ ref: AuditMessageRef, from responseSummary: String) -> AuditMessageRef {
        guard let obj = jsonObject(responseSummary) else { return ref }
        let parsedSubjectAccess = auditAccess(obj["subjectAccess"])
        let parsedBodyAccess = auditAccess(obj["bodyAccess"])
        let parsedRules = sanitizedRules(from: obj["sanitizedRules"])
        let parsedStealth = (obj["note"] as? String)?.contains("substituted") == true
        let mergedConditional = mergeConditionalFields(
            recorded: ref.conditionalFields,
            parsed: conditionalFields(from: obj)
        )
        let mergedBlocked = mergeConditionalFields(
            recorded: ref.conditionalBlockedFields,
            parsed: conditionalBlockedFields(from: obj)
        )

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
            || mergedConditional != nil
            || mergedBlocked != nil
        else { return ref }

        let recovered = Self.recoverStealthBodies(ref: ref, response: obj, stealth: mergedStealth == true)

        return AuditMessageRef(
            accountID: ref.accountID,
            placement: ref.placement,
            id: ref.id,
            subject: recovered.subject,
            from: ref.from,
            date: ref.date,
            to: ref.to,
            cc: ref.cc,
            bodySnippet: recovered.bodySnippet,
            subjectAccess: Self.preferHumanAccess(
                recorded: ref.subjectAccess,
                parsed: parsedSubjectAccess,
                stealth: mergedStealth == true,
                hasLeakEvidence: recovered.subjectOriginal != nil
                    || (ref.leakDetections ?? []).contains { $0.field == .subject }
            ),
            bodyAccess: Self.preferHumanAccess(
                recorded: ref.bodyAccess,
                parsed: parsedBodyAccess,
                stealth: mergedStealth == true,
                hasLeakEvidence: recovered.bodyOriginal != nil
                    || (ref.leakDetections ?? []).contains { $0.field == .body }
            ) ?? ref.bodyAccess,
            subjectOriginal: recovered.subjectOriginal,
            bodyOriginal: recovered.bodyOriginal,
            sanitizedRules: mergedRules,
            stealth: mergedStealth,
            leakDetections: ref.leakDetections,
            fields: ref.fields,
            attachments: ref.attachments,
            appliedRules: ref.appliedRules,
            conditionalFields: mergedConditional,
            conditionalBlockedFields: mergedBlocked,
            isPartial: ref.isPartial || (obj["isPartial"] as? Bool ?? false)
        )
    }

    /// Align Access Log field chips with `get_attachment` response access (and keep filename metadata).
    static func enrichAttachmentRef(_ ref: AuditMessageRef, from responseSummary: String) -> AuditMessageRef {
        guard let obj = jsonObject(responseSummary),
              let access = obj["attachmentContentAccess"] as? String
        else { return ref }

        var fields = ref.fields
        switch access {
        case "granted", "not_available", "too_large":
            fields.attachmentMetadata = true
            fields.attachmentContent = true
        case "not_granted":
            fields.attachmentContent = false
            if obj["filename"] as? String != nil {
                fields.attachmentMetadata = true
            }
        default:
            break
        }

        let attachments: [MailAttachment]
        if !ref.attachments.isEmpty {
            attachments = ref.attachments
        } else {
            attachments = parseAttachments(from: obj)
        }

        guard fields != ref.fields || attachments != ref.attachments else { return ref }

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
            subjectAccess: ref.subjectAccess,
            bodyAccess: ref.bodyAccess,
            subjectOriginal: ref.subjectOriginal,
            bodyOriginal: ref.bodyOriginal,
            sanitizedRules: ref.sanitizedRules,
            stealth: ref.stealth,
            leakDetections: ref.leakDetections,
            fields: fields,
            attachments: attachments,
            appliedRules: ref.appliedRules,
            conditionalFields: ref.conditionalFields,
            conditionalBlockedFields: ref.conditionalBlockedFields,
            isPartial: ref.isPartial || (obj["isPartial"] as? Bool ?? false)
        )
    }

    /// Older stealth audits stored original as bodySnippet. Prefer agent text from response JSON.
    private static func recoverStealthBodies(
        ref: AuditMessageRef,
        response: [String: Any],
        stealth: Bool
    ) -> (
        subject: String,
        subjectOriginal: String?,
        bodySnippet: String,
        bodyOriginal: String?
    ) {
        var subject = ref.subject
        var subjectOriginal = ref.subjectOriginal
        var bodySnippet = ref.bodySnippet
        var bodyOriginal = ref.bodyOriginal

        guard stealth else {
            return (subject, subjectOriginal, bodySnippet, bodyOriginal)
        }

        if let responseBody = response["body"] as? String, !responseBody.isEmpty {
            let capped = String(responseBody.prefix(AuditMessageRef.bodySnippetCap))
            if let original = bodyOriginal, original != responseBody {
                bodySnippet = capped
            } else if bodyOriginal == nil, capped != ref.bodySnippet {
                bodyOriginal = ref.bodySnippet
                bodySnippet = capped
            } else if bodyOriginal == ref.bodySnippet, capped != ref.bodySnippet {
                bodySnippet = capped
            }
        }

        if let responseSubject = response["subject"] as? String, !responseSubject.isEmpty {
            if let original = subjectOriginal, original != responseSubject {
                subject = responseSubject
            } else if subjectOriginal == nil, responseSubject != ref.subject {
                subjectOriginal = ref.subject
                subject = responseSubject
            } else if subjectOriginal == ref.subject, responseSubject != ref.subject {
                subject = responseSubject
            }
        }

        return (subject, subjectOriginal, bodySnippet, bodyOriginal)
    }

    /// Prefer audit-recorded human access over agent-facing JSON.
    /// Stealth responses report `granted` to the agent; Access Log must keep sanitized.
    private static func preferHumanAccess(
        recorded: AuditBodyAccess?,
        parsed: AuditBodyAccess?,
        stealth: Bool,
        hasLeakEvidence: Bool
    ) -> AuditBodyAccess? {
        if let recorded, recorded == .sanitized || recorded == .withheldConfidential {
            return recorded
        }
        if stealth, hasLeakEvidence {
            if recorded == .granted || recorded == nil, parsed == .granted || parsed == nil {
                return .sanitized
            }
        }
        if let recorded { return recorded }
        return parsed
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
        let attachmentContent = obj["attachmentContentAccess"] as? String == "granted"
        let attachmentMetadata =
            obj["attachmentAccess"] as? String == "granted"
            || attachmentContent
            || obj["filename"] as? String != nil
        return GrantFields(
            subject: obj["subjectAccess"] as? String != AuditBodyAccess.notGranted.rawValue,
            from: (obj["from"] as? String)?.isEmpty == false,
            to: (obj["to"] as? String)?.isEmpty == false,
            cc: (obj["cc"] as? String)?.isEmpty == false,
            date: (obj["date"] as? String)?.isEmpty == false,
            body: obj["bodyAccess"] as? String != AuditBodyAccess.notGranted.rawValue,
            attachmentMetadata: attachmentMetadata,
            attachmentContent: attachmentContent
        )
    }

    /// Ask-allowed fields from agent JSON (`conditionalAccessFields` / `*AccessReason`).
    private static func conditionalFields(from obj: [String: Any]) -> GrantFields? {
        var fields = GrantFields.none
        applyConditionalLabels(obj["conditionalAccessFields"], to: &fields)
        if obj["subjectAccessReason"] as? String == "conditional" {
            fields.subject = true
        }
        if obj["bodyAccessReason"] as? String == "conditional" {
            fields.body = true
        }
        return fields.hasAnyGranted ? fields : nil
    }

    /// Ask-blocked fields from agent JSON (`conditionalBlockedFields` / `*AccessReason`).
    private static func conditionalBlockedFields(from obj: [String: Any]) -> GrantFields? {
        var fields = GrantFields.none
        applyConditionalLabels(obj["conditionalBlockedFields"], to: &fields)
        if obj["subjectAccessReason"] as? String == "conditional_blocked" {
            fields.subject = true
        }
        if obj["bodyAccessReason"] as? String == "conditional_blocked" {
            fields.body = true
        }
        return fields.hasAnyGranted ? fields : nil
    }

    private static func applyConditionalLabels(_ raw: Any?, to fields: inout GrantFields) {
        guard let labels = raw as? [String] else { return }
        for label in labels {
            switch label {
            case "Subject": fields.subject = true
            case "From": fields.from = true
            case "To": fields.to = true
            case "Cc": fields.cc = true
            case "Date": fields.date = true
            case "Body": fields.body = true
            case "Attachment names": fields.attachmentMetadata = true
            case "Attachment content": fields.attachmentContent = true
            default: break
            }
        }
    }

    private static func mergeConditionalFields(
        recorded: GrantFields?,
        parsed: GrantFields?
    ) -> GrantFields? {
        switch (recorded, parsed) {
        case let (recorded?, parsed?):
            let merged = recorded.unioning(parsed)
            return merged.hasAnyGranted ? merged : nil
        case let (recorded?, nil):
            return recorded.hasAnyGranted ? recorded : nil
        case let (nil, parsed?):
            return parsed
        case (nil, nil):
            return nil
        }
    }

    private static func parseAttachments(from obj: [String: Any]) -> [MailAttachment] {
        if let items = obj["attachments"] as? [[String: Any]] {
            return items.compactMap { item in
                guard let filename = item["filename"] as? String else { return nil }
                let byteCount = intValue(item["byteCount"]) ?? 0
                return MailAttachment(filename: filename, byteCount: byteCount)
            }
        }
        if let filename = obj["filename"] as? String {
            return [MailAttachment(filename: filename, byteCount: intValue(obj["byteCount"]) ?? 0)]
        }
        return []
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
                    .font(.caption)
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
                    font: .caption
                )
            case .withheldConfidential:
                WithheldLabel(original: original, rules: leakGuard?.sanitizedRules)
            default:
                Text(AccessLogFormat.displayValue(key, text, accountLabel: accountLabel))
                    .font(.caption)
                    .textSelection(.enabled)
            }
        } else {
            Text(AccessLogFormat.displayValue(key, text, accountLabel: accountLabel))
                .font(.caption)
                .textSelection(.enabled)
        }
    }

    @ViewBuilder
    private func accessBadge(_ raw: String) -> some View {
        if let access = AuditBodyAccess(rawValue: raw) {
            switch access {
            case .sanitized, .withheldConfidential:
                Text(raw)
                    .font(.caption)
                    .foregroundStyle(SanitizedFieldStyle.legend)
            default:
                Text(raw)
                    .font(.caption)
                    .textSelection(.enabled)
            }
        } else {
            Text(raw)
                .font(.caption)
                .textSelection(.enabled)
        }
    }
}
