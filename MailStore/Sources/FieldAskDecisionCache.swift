import Foundation

/// Who may reuse a cached Ask Allow/Block for the same message + field.
public enum AskDecisionCacheShareScope: String, Sendable, Codable, CaseIterable {
    /// Only the deciding pairing `agentID` reuses the entry (MCP and CLI on that id share it).
    case perAgent
    /// Any paired agent may reuse another agent’s entry for the same message + field.
    case allAgents
}

/// Settings-driven policy for the field Ask cache on `get`.
public struct AskDecisionCachePolicy: Equatable, Sendable {
    public var enabled: Bool
    /// `nil` → no wall-clock expiry (forever or until quit; see `persistAcrossLaunches`).
    public var ttlSeconds: TimeInterval?
    /// When false, decisions stay in memory only (Until MailGent quits).
    public var persistAcrossLaunches: Bool
    public var shareScope: AskDecisionCacheShareScope

    public init(
        enabled: Bool = false,
        ttlSeconds: TimeInterval? = 3_600,
        persistAcrossLaunches: Bool = true,
        shareScope: AskDecisionCacheShareScope = .perAgent
    ) {
        self.enabled = enabled
        self.ttlSeconds = ttlSeconds
        self.persistAcrossLaunches = persistAcrossLaunches
        self.shareScope = shareScope
    }

    public static let disabled = AskDecisionCachePolicy(enabled: false)
}

/// Ask Allow/Block per field for one message (and agent, unless share scope is all).
/// Not a standing grant — TTL / quit / forget clears it. Consult only after Scope + overlays.
/// Wall-clock / forever decisions may persist to `ask-decisions.json`; until-quit stays memory-only.
public final class FieldAskDecisionCache: @unchecked Sendable {
    public struct Key: Hashable, Sendable {
        public let agentID: String
        public let accountID: String
        public let placement: String
        public let messageID: String
        public let field: String

        public init(
            agentID: String,
            accountID: String,
            placement: String,
            messageID: String,
            field: String
        ) {
            self.agentID = agentID
            self.accountID = accountID
            self.placement = placement
            self.messageID = messageID
            self.field = field
        }
    }

    private struct Entry: Sendable {
        let decision: ConditionalAccessDecision
        let storedAt: Date
        /// `nil` → no wall expiry (forever on disk, or until-quit in memory).
        let expiresAt: Date?
        let persistAcrossLaunches: Bool
    }

    private struct FileDocument: Codable {
        var version: Int
        var entries: [PersistedEntry]
    }

    private struct PersistedEntry: Codable {
        var agentID: String
        var accountID: String
        var placement: String
        var messageID: String
        var field: String
        var decision: ConditionalAccessDecision
        var storedAt: Date
        var expiresAt: Date?
    }

    private static let documentVersion = 1

    private let lock = NSLock()
    private var entries: [Key: Entry] = [:]
    private let fileURL: URL?

    public init(fileURL: URL? = nil, now: Date = Date()) {
        self.fileURL = fileURL
        lock.lock()
        loadLocked(now: now)
        lock.unlock()
    }

    public func decision(
        agentID: String,
        accountID: String,
        placement: String,
        messageID: String,
        field: String,
        policy: AskDecisionCachePolicy,
        now: Date = Date()
    ) -> ConditionalAccessDecision? {
        guard policy.enabled else { return nil }
        lock.lock()
        defer { lock.unlock() }
        switch policy.shareScope {
        case .perAgent:
            let key = Key(
                agentID: agentID,
                accountID: accountID,
                placement: placement,
                messageID: messageID,
                field: field
            )
            return liveDecision(for: key, now: now)
        case .allAgents:
            var found: ConditionalAccessDecision?
            var pruned = false
            for (key, entry) in entries {
                guard key.accountID == accountID,
                      key.placement == placement,
                      key.messageID == messageID,
                      key.field == field
                else { continue }
                if isLive(entry, now: now) {
                    found = entry.decision
                    break
                }
                entries.removeValue(forKey: key)
                pruned = true
            }
            if pruned {
                persistLocked()
            }
            return found
        }
    }

    public func store(
        _ decision: ConditionalAccessDecision,
        agentID: String,
        accountID: String,
        placement: String,
        messageID: String,
        field: String,
        policy: AskDecisionCachePolicy,
        now: Date = Date()
    ) {
        let key = Key(
            agentID: agentID,
            accountID: accountID,
            placement: placement,
            messageID: messageID,
            field: field
        )
        let expiresAt = policy.ttlSeconds.map { now.addingTimeInterval($0) }
        lock.lock()
        entries[key] = Entry(
            decision: decision,
            storedAt: now,
            expiresAt: expiresAt,
            persistAcrossLaunches: policy.persistAcrossLaunches
        )
        if policy.persistAcrossLaunches {
            persistLocked()
        }
        lock.unlock()
    }

    public func removeAll(forAgentID agentID: String) {
        lock.lock()
        entries = entries.filter { $0.key.agentID != agentID }
        persistLocked()
        lock.unlock()
    }

    public func removeAll() {
        lock.lock()
        entries.removeAll()
        persistLocked()
        lock.unlock()
    }

    private func liveDecision(for key: Key, now: Date) -> ConditionalAccessDecision? {
        guard let entry = entries[key] else { return nil }
        if isLive(entry, now: now) {
            return entry.decision
        }
        entries.removeValue(forKey: key)
        persistLocked()
        return nil
    }

    private func isLive(_ entry: Entry, now: Date) -> Bool {
        guard let expiresAt = entry.expiresAt else { return true }
        return now <= expiresAt
    }

    private func loadLocked(now: Date) {
        guard
            let fileURL,
            let data = try? Data(contentsOf: fileURL),
            let document = try? Self.decoder().decode(FileDocument.self, from: data),
            document.version == Self.documentVersion
        else { return }

        var loaded: [Key: Entry] = [:]
        var droppedExpired = false
        for row in document.entries {
            let key = Key(
                agentID: row.agentID,
                accountID: row.accountID,
                placement: row.placement,
                messageID: row.messageID,
                field: row.field
            )
            let entry = Entry(
                decision: row.decision,
                storedAt: row.storedAt,
                expiresAt: row.expiresAt,
                persistAcrossLaunches: true
            )
            if isLive(entry, now: now) {
                loaded[key] = entry
            } else {
                droppedExpired = true
            }
        }
        entries = loaded
        if droppedExpired {
            persistLocked()
        }
    }

    private func persistLocked() {
        guard let fileURL else { return }
        let persistable = entries.filter(\.value.persistAcrossLaunches)
        if persistable.isEmpty {
            try? FileManager.default.removeItem(at: fileURL)
            return
        }
        let document = FileDocument(
            version: Self.documentVersion,
            entries: persistable.map { key, entry in
                PersistedEntry(
                    agentID: key.agentID,
                    accountID: key.accountID,
                    placement: key.placement,
                    messageID: key.messageID,
                    field: key.field,
                    decision: entry.decision,
                    storedAt: entry.storedAt,
                    expiresAt: entry.expiresAt
                )
            }
        )
        do {
            try FileManager.default.createDirectory(
                at: fileURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            let data = try Self.encoder().encode(document)
            try data.write(to: fileURL, options: .atomic)
        } catch {
            // Keep in-memory map; disk is best-effort.
        }
    }

    private static func encoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        return encoder
    }

    private static func decoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}
