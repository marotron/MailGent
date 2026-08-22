import MailStore
import SwiftUI

struct AccessLogView: View {
    @Bindable var session: CompanionSession
    var initialSelection: String?

    @State private var selectedID: String?
    @State private var agentFilter = AgentFilter.all
    @State private var timeFilter = TimeFilter.all

    var body: some View {
        VStack(spacing: 0) {
            filterBar
            Divider()
            HSplitView {
                logList
                    .frame(minWidth: 260, idealWidth: 300, maxHeight: .infinity)
                detailPane
                    .frame(minWidth: 340, maxHeight: .infinity)
            }
        }
        .frame(minWidth: 720, minHeight: 420)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear(perform: applyInitialSelection)
        .onChange(of: session.agents.auditRevision) { _, _ in reconcileSelection() }
        .onChange(of: agentFilter) { _, _ in reconcileSelection() }
        .onChange(of: timeFilter) { _, _ in reconcileSelection() }
    }

    private var entries: [AuditEntry] {
        session.agents.allAudit
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

    private var filterBar: some View {
        HStack(spacing: 12) {
            Picker("Agent", selection: $agentFilter) {
                Text("All agents").tag(AgentFilter.all)
                ForEach(agentNames, id: \.self) { name in
                    Text(name).tag(AgentFilter.named(name))
                }
            }
            .frame(maxWidth: 200)

            Picker("Time", selection: $timeFilter) {
                ForEach(TimeFilter.allCases) { filter in
                    Text(filter.title).tag(filter)
                }
            }
            .frame(maxWidth: 180)

            Spacer()
            Text(countLabel)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .pickerStyle(.menu)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    private var countLabel: String {
        if filtered.count == entries.count {
            return "\(entries.count)"
        }
        return "\(filtered.count) of \(entries.count)"
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
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text(entry.kind.rawValue)
                .font(.caption.monospaced())
                .foregroundStyle(outcomeColor)
            Text(entry.agentName)
                .font(.caption)
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
    }

    private var outcomeColor: Color {
        switch entry.outcome {
        case .ok: .primary
        case .error: .orange
        }
    }

    private var timeLabel: String {
        if Calendar.current.isDateInToday(entry.at) {
            return entry.at.formatted(date: .omitted, time: .shortened)
        }
        return entry.at.formatted(date: .numeric, time: .shortened)
    }
}

private struct AccessLogDetail: View {
    @Bindable var session: CompanionSession
    let entry: AuditEntry

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                header
                compactField("Request", text: requestLine)
                compactField("Response", text: responseLine)
                if !entry.messages.isEmpty {
                    section("Messages") {
                        VStack(alignment: .leading, spacing: 4) {
                            ForEach(entry.messages, id: \.rowID) { ref in
                                Button {
                                    session.openRead(
                                        accountID: ref.accountID,
                                        placement: ref.placement,
                                        id: ref.id
                                    )
                                    DetachedWindowHost.shared.showCompanion(session: session)
                                } label: {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(ref.subject.isEmpty ? "(no subject)" : ref.subject)
                                            .font(.callout.weight(.medium))
                                            .lineLimit(2)
                                        Text(messageMeta(ref))
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                            .lineLimit(1)
                                    }
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)
                                .help("Open in Companion Read")
                            }
                        }
                    }
                }
                if !entry.placements.isEmpty {
                    section("Placements") {
                        VStack(alignment: .leading, spacing: 4) {
                            ForEach(entry.placements, id: \.rowID) { ref in
                                Text("\(ref.accountID)/\(ref.placement)")
                                    .font(.caption.monospaced())
                                    .textSelection(.enabled)
                            }
                        }
                    }
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(entry.kind.rawValue)
                    .font(.headline.monospaced())
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
        switch entry.outcome {
        case .ok:
            Text("ok")
                .font(.caption.weight(.semibold).monospaced())
                .foregroundStyle(.green)
        case .error(let message):
            Text("error: \(message)")
                .font(.caption.weight(.semibold).monospaced())
                .foregroundStyle(.orange)
                .lineLimit(2)
        }
    }

    private func compactField(_ title: String, text: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            Text(text)
                .font(.callout.monospaced())
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
                .background(.background, in: RoundedRectangle(cornerRadius: 8))
                .overlay {
                    RoundedRectangle(cornerRadius: 8).stroke(.separator)
                }
        }
    }

    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            content()
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(8)
                .background(.background, in: RoundedRectangle(cornerRadius: 8))
                .overlay {
                    RoundedRectangle(cornerRadius: 8).stroke(.separator)
                }
        }
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

    private func messageMeta(_ ref: AuditMessageRef) -> String {
        var parts: [String] = []
        if !ref.from.isEmpty { parts.append(ref.from) }
        parts.append("\(ref.accountID)/\(ref.placement)")
        if !ref.date.isEmpty { parts.append(ref.date) }
        return parts.joined(separator: " · ")
    }
}
