import Foundation

public enum AuditKind: String, Codable, Equatable, Hashable, Sendable {
    case pair
    case search
    case list
    case listNew
    case listPlacements
    case get
    case createDraft
    case updateDraft
    case updateIndex
    case status
    case setSource = "set_source"
    case revoke
}

public enum AuditOutcome: Equatable, Sendable {
    case ok
    case error(String)
}

public enum AuditBodyAccess: String, Codable, Equatable, Hashable, Sendable {
    case granted
    case notGranted = "not_granted"
    case notAvailable = "not_available"
    case sanitized
    case withheldConfidential = "withheld_confidential"
}

/// One leak-guard hit recorded for the Access Log (human-facing).
public struct AuditLeakDetection: Equatable, Hashable, Codable, Sendable {
    public enum Field: String, Codable, Sendable {
        case subject
        case body
    }

    public enum Disposition: String, Codable, Sendable {
        case redacted
        case replaced
        case withheld
    }

    public let field: Field
    public let label: String
    public let disposition: Disposition
    public let discloseToAgent: Bool

    public init(
        field: Field,
        label: String,
        disposition: Disposition,
        discloseToAgent: Bool
    ) {
        self.field = field
        self.label = label
        self.disposition = disposition
        self.discloseToAgent = discloseToAgent
    }

    public static func from(
        subject: SanitizedField?,
        body: SanitizedField?
    ) -> [AuditLeakDetection]? {
        var out: [AuditLeakDetection] = []
        if let subject {
            out.append(contentsOf: from(field: .subject, sanitized: subject))
        }
        if let body {
            out.append(contentsOf: from(field: .body, sanitized: body))
        }
        return out.isEmpty ? nil : out
    }

    private static func from(field: Field, sanitized: SanitizedField) -> [AuditLeakDetection] {
        let withheld = sanitized.access == .withheldConfidential
        return sanitized.hitSpans.map { hit in
            let disposition: Disposition
            if withheld {
                disposition = .withheld
            } else if hit.action == .replace {
                disposition = .replaced
            } else {
                disposition = .redacted
            }
            return AuditLeakDetection(
                field: field,
                label: hit.label,
                disposition: disposition,
                discloseToAgent: hit.discloseToAgent
            )
        }
    }
}

public struct AuditRetention: Equatable, Sendable {
    public var maxAge: TimeInterval?
    public var maxCount: Int?
    public var maxBytes: Int?

    public static let unlimited = AuditRetention()

    public init(
        maxAge: TimeInterval? = nil,
        maxCount: Int? = nil,
        maxBytes: Int? = nil
    ) {
        self.maxAge = Self.positive(maxAge)
        self.maxCount = Self.positive(maxCount)
        self.maxBytes = Self.positive(maxBytes)
    }

    private static func positive(_ value: TimeInterval?) -> TimeInterval? {
        guard let value, value > 0 else { return nil }
        return value
    }

    private static func positive(_ value: Int?) -> Int? {
        guard let value, value > 0 else { return nil }
        return value
    }
}

public struct AuditMessageRef: Equatable, Hashable, Sendable {
    public static let bodySnippetCap = 280

    public let accountID: String
    public let placement: String
    public let id: String
    public let subject: String
    public let from: String
    public let to: String
    public let cc: String
    public let date: String
    public let bodySnippet: String
    public let subjectAccess: AuditBodyAccess?
    public let bodyAccess: AuditBodyAccess
    public let subjectOriginal: String?
    public let bodyOriginal: String?
    public let sanitizedRules: [String]?
    public let stealth: Bool?
    public let leakDetections: [AuditLeakDetection]?
    public let fields: GrantFields
    public let attachments: [MailAttachment]

    public init(
        accountID: String,
        placement: String,
        id: String,
        subject: String,
        from: String,
        date: String,
        to: String = "",
        cc: String = "",
        bodySnippet: String = "",
        subjectAccess: AuditBodyAccess? = nil,
        bodyAccess: AuditBodyAccess = .notAvailable,
        subjectOriginal: String? = nil,
        bodyOriginal: String? = nil,
        sanitizedRules: [String]? = nil,
        stealth: Bool? = nil,
        leakDetections: [AuditLeakDetection]? = nil,
        fields: GrantFields = .headersOnly,
        attachments: [MailAttachment] = []
    ) {
        self.accountID = accountID
        self.placement = placement
        self.id = id
        self.subject = subject
        self.from = from
        self.to = to
        self.cc = cc
        self.date = date
        self.bodySnippet = bodySnippet
        self.subjectAccess = subjectAccess
        self.bodyAccess = bodyAccess
        self.subjectOriginal = subjectOriginal
        self.bodyOriginal = bodyOriginal
        self.sanitizedRules = sanitizedRules
        self.stealth = stealth
        self.leakDetections = leakDetections
        self.fields = fields
        self.attachments = attachments
    }

    public var rowID: String { "\(accountID)/\(placement)/\(id)" }

    /// Count of leak-guard parts for list badges. Prefers recorded hits; falls back for older logs.
    public var leakDetectionCount: Int {
        if let leakDetections, !leakDetections.isEmpty {
            return leakDetections.count
        }
        if let sanitizedRules, !sanitizedRules.isEmpty {
            return sanitizedRules.count
        }
        if stealth == true
            || subjectAccess == .sanitized
            || subjectAccess == .withheldConfidential
            || bodyAccess == .sanitized
            || bodyAccess == .withheldConfidential
        {
            return 1
        }
        return 0
    }

    /// Rows shown in Access Log detail (recorded hits, or a legacy proxy from rule labels).
    public var displayLeakDetections: [AuditLeakDetection] {
        if let leakDetections, !leakDetections.isEmpty {
            return leakDetections
        }
        guard leakDetectionCount > 0 else { return [] }
        let withheldSubject = subjectAccess == .withheldConfidential
        let withheldBody = bodyAccess == .withheldConfidential
        let disposition: AuditLeakDetection.Disposition
        if withheldSubject || withheldBody {
            disposition = .withheld
        } else if stealth == true {
            disposition = .replaced
        } else {
            disposition = .redacted
        }
        let field: AuditLeakDetection.Field =
            (bodyAccess == .sanitized || bodyAccess == .withheldConfidential || stealth == true)
                ? .body
                : .subject
        if let sanitizedRules, !sanitizedRules.isEmpty {
            return sanitizedRules.map {
                AuditLeakDetection(
                    field: field,
                    label: $0,
                    disposition: disposition,
                    discloseToAgent: stealth != true
                )
            }
        }
        return [
            AuditLeakDetection(
                field: field,
                label: stealth == true ? "Stealth replace" : "Sensitive content",
                disposition: disposition,
                discloseToAgent: stealth != true
            )
        ]
    }

    public var attachmentNamesDetail: String {
        if attachments.isEmpty { return "none in this response" }
        return attachments.map { "\($0.filename) · \($0.sizeLabel)" }.joined(separator: ", ")
    }
}

public struct AuditPlacementRef: Equatable, Hashable, Codable, Sendable {
    public let accountID: String
    public let placement: String

    public init(accountID: String, placement: String) {
        self.accountID = accountID
        self.placement = placement
    }

    public var rowID: String { "\(accountID)/\(placement)" }
}

public struct AuditEntry: Equatable, Sendable, Identifiable {
    public let id: String
    public let kind: AuditKind
    public let agentID: String
    public let agentName: String
    public let detail: String
    public let at: Date
    public let finishedAt: Date?
    public let requestSummary: String
    public let responseSummary: String
    public let messages: [AuditMessageRef]
    public let placements: [AuditPlacementRef]
    public let outcome: AuditOutcome

    public init(
        id: String = UUID().uuidString,
        kind: AuditKind,
        agentID: String,
        agentName: String,
        detail: String = "",
        at: Date = Date(),
        finishedAt: Date? = nil,
        requestSummary: String = "",
        responseSummary: String = "",
        messages: [AuditMessageRef] = [],
        placements: [AuditPlacementRef] = [],
        outcome: AuditOutcome = .ok
    ) {
        self.id = id
        self.kind = kind
        self.agentID = agentID
        self.agentName = agentName
        self.detail = detail
        self.at = at
        self.finishedAt = finishedAt
        self.requestSummary = requestSummary
        self.responseSummary = responseSummary
        self.messages = messages
        self.placements = placements
        self.outcome = outcome
    }

    public var duration: TimeInterval? {
        guard let finishedAt else { return nil }
        return finishedAt.timeIntervalSince(at)
    }

    func withSummaries(request: String, response: String) -> AuditEntry {
        AuditEntry(
            id: id,
            kind: kind,
            agentID: agentID,
            agentName: agentName,
            detail: detail,
            at: at,
            finishedAt: finishedAt,
            requestSummary: request,
            responseSummary: response,
            messages: messages,
            placements: placements,
            outcome: outcome
        )
    }
}

public final class AuditLog: @unchecked Sendable {
    public static let messageRefCap = 25

    public var policy: AuditRetention
    private let fileURL: URL?
    private var storage: [AuditEntry] = []
    private let lock = NSLock()
    /// Fired after each mutation (any thread). Bridge uses this to bump UI revision.
    public var onChange: (@Sendable () -> Void)?

    public init(fileURL: URL? = nil, policy: AuditRetention = .unlimited) {
        self.fileURL = fileURL
        self.policy = policy
        lock.lock()
        loadLocked()
        let trimmed = Self.trimmed(storage, policy: policy, now: Date())
        let changed = trimmed != storage
        storage = trimmed
        lock.unlock()
        if changed {
            persist()
        }
    }

    public func append(_ entry: AuditEntry) {
        mutate { storage in
            storage.append(entry)
        }
    }

    /// Overwrite summaries on the newest entry when it matches `kind`.
    /// Used by the MCP layer to store the exact tool JSON the agent received.
    public func updateLast(
        kind: AuditKind,
        requestSummary: String? = nil,
        responseSummary: String? = nil
    ) {
        mutate { storage in
            guard let last = storage.last, last.kind == kind else { return }
            storage[storage.count - 1] = last.withSummaries(
                request: requestSummary ?? last.requestSummary,
                response: responseSummary ?? last.responseSummary
            )
        }
    }

    public func removeAll() {
        mutate { storage in
            storage.removeAll()
        }
    }

    public func removeOlderThan(_ date: Date) {
        mutate { storage in
            storage.removeAll { $0.at < date }
        }
    }

    public func applyRetention(now: Date = Date()) {
        mutate(now: now) { _ in }
    }

    public func entries() -> [AuditEntry] {
        lock.lock()
        defer { lock.unlock() }
        return storage
    }

    public func byteCount() -> Int {
        lock.lock()
        defer { lock.unlock() }
        if storage.isEmpty { return 0 }
        return (try? Self.encode(storage).count) ?? 0
    }

    private func mutate(now: Date = Date(), _ body: (inout [AuditEntry]) -> Void) {
        lock.lock()
        let before = storage
        body(&storage)
        storage = Self.trimmed(storage, policy: policy, now: now)
        let snapshot = storage
        let changed = snapshot != before
        lock.unlock()
        guard changed else { return }
        persist(snapshot)
        onChange?()
    }

    private func loadLocked() {
        guard
            let fileURL,
            let data = try? Data(contentsOf: fileURL),
            let file = try? Self.decoder().decode(AuditLogFile.self, from: data)
        else { return }
        storage = file.entries
    }

    private func persist() {
        lock.lock()
        let snapshot = storage
        lock.unlock()
        persist(snapshot)
    }

    private func persist(_ entries: [AuditEntry]) {
        guard let fileURL else { return }
        if entries.isEmpty {
            try? FileManager.default.removeItem(at: fileURL)
            return
        }
        do {
            try FileManager.default.createDirectory(
                at: fileURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try Self.encode(entries).write(to: fileURL, options: .atomic)
        } catch {
            // Keep the in-memory log; disk is best-effort.
        }
    }

    static func trimmed(
        _ entries: [AuditEntry],
        policy: AuditRetention,
        now: Date
    ) -> [AuditEntry] {
        var kept = entries
        if let maxAge = policy.maxAge {
            let cutoff = now.addingTimeInterval(-maxAge)
            kept.removeAll { $0.at < cutoff }
        }
        if let maxCount = policy.maxCount, kept.count > maxCount {
            kept = Array(kept.suffix(maxCount))
        }
        if let maxBytes = policy.maxBytes {
            var encoded = (try? encode(kept)) ?? Data()
            while kept.count > 1, encoded.count > maxBytes {
                kept.removeFirst()
                encoded = (try? encode(kept)) ?? Data()
            }
        }
        return kept
    }

    private static func encode(_ entries: [AuditEntry]) throws -> Data {
        try encoder().encode(AuditLogFile(entries: entries))
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

private struct AuditLogFile: Codable {
    var entries: [AuditEntry]
}

extension AuditOutcome: Codable {
    enum CodingKeys: String, CodingKey {
        case type
        case message
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decodeIfPresent(String.self, forKey: .type) ?? "ok"
        if type == "error" {
            self = .error(try container.decodeIfPresent(String.self, forKey: .message) ?? "")
        } else {
            self = .ok
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .ok:
            try container.encode("ok", forKey: .type)
        case .error(let message):
            try container.encode("error", forKey: .type)
            try container.encode(message, forKey: .message)
        }
    }
}

extension AuditMessageRef: Codable {
    enum CodingKeys: String, CodingKey {
        case accountID, placement, id, subject, from, to, cc, date
        case bodySnippet, subjectAccess, bodyAccess, subjectOriginal, bodyOriginal
        case sanitizedRules, stealth, leakDetections, fields, attachments
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        accountID = try container.decode(String.self, forKey: .accountID)
        placement = try container.decode(String.self, forKey: .placement)
        id = try container.decode(String.self, forKey: .id)
        subject = try container.decode(String.self, forKey: .subject)
        from = try container.decode(String.self, forKey: .from)
        date = try container.decode(String.self, forKey: .date)
        to = try container.decodeIfPresent(String.self, forKey: .to) ?? ""
        cc = try container.decodeIfPresent(String.self, forKey: .cc) ?? ""
        bodySnippet = try container.decodeIfPresent(String.self, forKey: .bodySnippet) ?? ""
        subjectAccess = try container.decodeIfPresent(AuditBodyAccess.self, forKey: .subjectAccess)
        bodyAccess = try container.decodeIfPresent(AuditBodyAccess.self, forKey: .bodyAccess)
            ?? .notAvailable
        subjectOriginal = try container.decodeIfPresent(String.self, forKey: .subjectOriginal)
        bodyOriginal = try container.decodeIfPresent(String.self, forKey: .bodyOriginal)
        sanitizedRules = try container.decodeIfPresent([String].self, forKey: .sanitizedRules)
        stealth = try container.decodeIfPresent(Bool.self, forKey: .stealth)
        leakDetections = try container.decodeIfPresent(
            [AuditLeakDetection].self,
            forKey: .leakDetections
        )
        fields = try container.decodeIfPresent(GrantFields.self, forKey: .fields) ?? .headersOnly
        attachments = try container.decodeIfPresent([MailAttachment].self, forKey: .attachments) ?? []
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(accountID, forKey: .accountID)
        try container.encode(placement, forKey: .placement)
        try container.encode(id, forKey: .id)
        try container.encode(subject, forKey: .subject)
        try container.encode(from, forKey: .from)
        try container.encode(to, forKey: .to)
        try container.encode(cc, forKey: .cc)
        try container.encode(date, forKey: .date)
        try container.encode(bodySnippet, forKey: .bodySnippet)
        try container.encodeIfPresent(subjectAccess, forKey: .subjectAccess)
        try container.encode(bodyAccess, forKey: .bodyAccess)
        try container.encodeIfPresent(subjectOriginal, forKey: .subjectOriginal)
        try container.encodeIfPresent(bodyOriginal, forKey: .bodyOriginal)
        try container.encodeIfPresent(sanitizedRules, forKey: .sanitizedRules)
        try container.encodeIfPresent(stealth, forKey: .stealth)
        try container.encodeIfPresent(leakDetections, forKey: .leakDetections)
        try container.encode(fields, forKey: .fields)
        try container.encode(attachments, forKey: .attachments)
    }
}

extension AuditEntry: Codable {}

extension AuditMessageRef {
    public init(
        _ message: IndexedMessage,
        fields: GrantFields = .headersOnly,
        subjectSanitized: SanitizedField? = nil
    ) {
        let access: AuditBodyAccess
        let snippet: String
        if !fields.body {
            access = .notGranted
            snippet = ""
        } else if message.body.isEmpty {
            access = .notAvailable
            snippet = ""
        } else {
            access = .granted
            snippet = String(message.body.prefix(Self.bodySnippetCap))
        }
        let subjectAccess = subjectSanitized?.access.auditBodyAccess
        let subjectOriginal = subjectSanitized.flatMap { field in
            field.original != field.text ? field.original : nil
        }
        self.init(
            accountID: message.accountID,
            placement: message.placement,
            id: message.id,
            subject: fields.subject ? message.subject : "",
            from: fields.from ? message.from : "",
            date: fields.date ? message.date : "",
            to: fields.to ? message.to : "",
            cc: fields.cc ? message.cc : "",
            bodySnippet: snippet,
            subjectAccess: subjectAccess,
            bodyAccess: access,
            subjectOriginal: subjectOriginal,
            leakDetections: AuditLeakDetection.from(subject: subjectSanitized, body: nil),
            fields: fields
        )
    }

    public init(
        _ message: ReadMessage,
        fields: GrantFields = .headersOnly,
        subjectSanitized: SanitizedField? = nil,
        bodySanitized: SanitizedField? = nil
    ) {
        let bodyAuditAccess: AuditBodyAccess
        let snippet: String
        if let bodySanitized {
            bodyAuditAccess = bodySanitized.access.auditBodyAccess
            snippet = String(bodySanitized.original.prefix(Self.bodySnippetCap))
        } else {
            switch message.body {
            case .text(let text):
                if text.isEmpty {
                    bodyAuditAccess = .notAvailable
                    snippet = ""
                } else {
                    bodyAuditAccess = .granted
                    snippet = String(text.prefix(Self.bodySnippetCap))
                }
            case .notAvailable:
                bodyAuditAccess = .notAvailable
                snippet = ""
            case .notGranted:
                bodyAuditAccess = .notGranted
                snippet = ""
            }
        }
        let subjectAccess = subjectSanitized?.access.auditBodyAccess
        let subjectOriginal = subjectSanitized.flatMap { field in
            field.original != field.text ? field.original : nil
        }
        let bodyOriginal = bodySanitized.flatMap { field in
            field.original != field.text ? field.original : nil
        }
        let disclosed = Array(
            Set((subjectSanitized?.disclosedRules ?? []) + (bodySanitized?.disclosedRules ?? []))
        ).sorted()
        let stealth = (subjectSanitized?.stealth == true) || (bodySanitized?.stealth == true)
        self.init(
            accountID: message.accountID,
            placement: message.placement,
            id: message.id,
            subject: message.subject,
            from: message.from,
            date: message.date,
            to: message.to,
            cc: message.cc,
            bodySnippet: snippet,
            subjectAccess: subjectAccess,
            bodyAccess: bodyAuditAccess,
            subjectOriginal: subjectOriginal,
            bodyOriginal: bodyOriginal,
            sanitizedRules: disclosed.isEmpty ? nil : disclosed,
            stealth: stealth ? true : nil,
            leakDetections: AuditLeakDetection.from(
                subject: subjectSanitized,
                body: bodySanitized
            ),
            fields: fields,
            attachments: message.attachments
        )
    }
}
