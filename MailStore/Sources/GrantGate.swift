import Foundation

public struct GrantParticipant: Equatable, Codable, Sendable {
    public enum Role: String, Codable, Sendable {
        case from
        case to
        case anyParticipant
    }

    public let role: Role
    /// Normalized email or domain (lowercase). Domains have no `@`.
    public let address: String

    public init(role: Role, address: String) {
        self.role = role
        self.address = Grant.normalizeAddress(address)
    }
}

public enum FieldAccessMode: String, Codable, Hashable, Sendable {
    case off
    case on
    case ask
    
    public var isAllowed: Bool {
        self == .on
    }
    
    public var requiresPrompt: Bool {
        self == .ask
    }
    
    public func nextMode() -> FieldAccessMode {
        switch self {
        case .off: return .ask
        case .ask: return .on
        case .on: return .off
        }
    }
}

public struct GrantFields: Equatable, Hashable, Sendable {
    public var subjectMode: FieldAccessMode
    public var fromMode: FieldAccessMode
    public var toMode: FieldAccessMode
    public var ccMode: FieldAccessMode
    public var dateMode: FieldAccessMode
    public var bodyMode: FieldAccessMode
    public var attachmentMetadataMode: FieldAccessMode
    public var attachmentContentMode: FieldAccessMode
    
    /// Legacy Bool getters for backward compatibility
    public var subject: Bool {
        get { subjectMode == .on }
        set { subjectMode = newValue ? .on : .off }
    }
    
    public var from: Bool {
        get { fromMode == .on }
        set { fromMode = newValue ? .on : .off }
    }
    
    public var to: Bool {
        get { toMode == .on }
        set { toMode = newValue ? .on : .off }
    }
    
    public var cc: Bool {
        get { ccMode == .on }
        set { ccMode = newValue ? .on : .off }
    }
    
    public var date: Bool {
        get { dateMode == .on }
        set { dateMode = newValue ? .on : .off }
    }
    
    public var body: Bool {
        get { bodyMode == .on }
        set { bodyMode = newValue ? .on : .off }
    }
    
    public var attachmentMetadata: Bool {
        get { attachmentMetadataMode == .on }
        set { attachmentMetadataMode = newValue ? .on : .off }
    }
    
    public var attachmentContent: Bool {
        get { attachmentContentMode == .on }
        set { attachmentContentMode = newValue ? .on : .off }
    }

    /// All header fields on/off (legacy “envelope” cap).
    public var envelope: Bool {
        get { subject && from && to && cc && date }
        set {
            subject = newValue
            from = newValue
            to = newValue
            cc = newValue
            date = newValue
        }
    }

    public init(
        subjectMode: FieldAccessMode = .on,
        fromMode: FieldAccessMode = .on,
        toMode: FieldAccessMode = .on,
        ccMode: FieldAccessMode = .on,
        dateMode: FieldAccessMode = .on,
        bodyMode: FieldAccessMode = .on,
        attachmentMetadataMode: FieldAccessMode = .off,
        attachmentContentMode: FieldAccessMode = .off
    ) {
        self.subjectMode = subjectMode
        self.fromMode = fromMode
        self.toMode = toMode
        self.ccMode = ccMode
        self.dateMode = dateMode
        self.bodyMode = bodyMode
        self.attachmentMetadataMode = attachmentMetadataMode
        self.attachmentContentMode = attachmentMetadataMode == .off ? .off : attachmentContentMode
    }
    
    public init(
        subject: Bool = true,
        from: Bool = true,
        to: Bool = true,
        cc: Bool = true,
        date: Bool = true,
        body: Bool = true,
        attachmentMetadata: Bool = false,
        attachmentContent: Bool = false
    ) {
        self.init(
            subjectMode: subject ? .on : .off,
            fromMode: from ? .on : .off,
            toMode: to ? .on : .off,
            ccMode: cc ? .on : .off,
            dateMode: date ? .on : .off,
            bodyMode: body ? .on : .off,
            attachmentMetadataMode: attachmentMetadata ? .on : .off,
            attachmentContentMode: attachmentContent ? .on : .off
        )
    }

    public init(
        envelope: Bool = true,
        body: Bool = true,
        attachmentMetadata: Bool = false,
        attachmentContent: Bool = false
    ) {
        self.init(
            subject: envelope,
            from: envelope,
            to: envelope,
            cc: envelope,
            date: envelope,
            body: body,
            attachmentMetadata: attachmentMetadata,
            attachmentContent: attachmentContent
        )
    }

    /// Full headers + body; attachments off (historic default).
    public static let `default` = GrantFields()

    /// List/metadata posture: headers on, body and attachments off.
    public static let headersOnly = GrantFields(
        subject: true,
        from: true,
        to: true,
        cc: true,
        date: true,
        body: false,
        attachmentMetadata: false,
        attachmentContent: false
    )

    /// No fields granted (rule-delta identity / empty mask).
    public static let none = GrantFields(
        subject: false,
        from: false,
        to: false,
        cc: false,
        date: false,
        body: false,
        attachmentMetadata: false,
        attachmentContent: false
    )

    /// Bits that are true here and false in `other`.
    public func bitsNotIn(_ other: GrantFields) -> GrantFields {
        GrantFields(
            subject: subject && !other.subject,
            from: from && !other.from,
            to: to && !other.to,
            cc: cc && !other.cc,
            date: date && !other.date,
            body: body && !other.body,
            attachmentMetadata: attachmentMetadata && !other.attachmentMetadata,
            attachmentContent: attachmentContent && !other.attachmentContent
        )
    }

    public var hasAnyGranted: Bool {
        subject || from || to || cc || date || body || attachmentMetadata || attachmentContent
    }
}

extension GrantFields: Codable {
    enum CodingKeys: String, CodingKey {
        case subject, from, to, cc, date, body, attachmentMetadata, attachmentContent, envelope
        case subjectMode, fromMode, toMode, ccMode, dateMode, bodyMode, attachmentMetadataMode, attachmentContentMode
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        
        // Try new mode-based fields first
        if c.contains(.subjectMode) {
            subjectMode = try c.decode(FieldAccessMode.self, forKey: .subjectMode)
            fromMode = try c.decode(FieldAccessMode.self, forKey: .fromMode)
            toMode = try c.decode(FieldAccessMode.self, forKey: .toMode)
            ccMode = try c.decode(FieldAccessMode.self, forKey: .ccMode)
            dateMode = try c.decode(FieldAccessMode.self, forKey: .dateMode)
            bodyMode = try c.decode(FieldAccessMode.self, forKey: .bodyMode)
            attachmentMetadataMode = try c.decode(FieldAccessMode.self, forKey: .attachmentMetadataMode)
            attachmentContentMode = try c.decode(FieldAccessMode.self, forKey: .attachmentContentMode)
        } else {
            // Legacy Bool-based decoding
            let bodyBool = try c.decodeIfPresent(Bool.self, forKey: .body) ?? true
            let attachmentMetadataBool = try c.decodeIfPresent(Bool.self, forKey: .attachmentMetadata) ?? false
            let attachmentContentBool = try c.decodeIfPresent(Bool.self, forKey: .attachmentContent) ?? false
            
            bodyMode = bodyBool ? .on : .off
            attachmentMetadataMode = attachmentMetadataBool ? .on : .off
            attachmentContentMode = attachmentContentBool ? .on : .off
            
            if c.contains(.subject) || c.contains(.from) || c.contains(.to) || c.contains(.cc) || c.contains(.date) {
                subjectMode = (try c.decodeIfPresent(Bool.self, forKey: .subject) ?? true) ? .on : .off
                fromMode = (try c.decodeIfPresent(Bool.self, forKey: .from) ?? true) ? .on : .off
                toMode = (try c.decodeIfPresent(Bool.self, forKey: .to) ?? true) ? .on : .off
                ccMode = (try c.decodeIfPresent(Bool.self, forKey: .cc) ?? true) ? .on : .off
                dateMode = (try c.decodeIfPresent(Bool.self, forKey: .date) ?? true) ? .on : .off
            } else {
                let envelope = try c.decodeIfPresent(Bool.self, forKey: .envelope) ?? true
                let envelopeMode: FieldAccessMode = envelope ? .on : .off
                subjectMode = envelopeMode
                fromMode = envelopeMode
                toMode = envelopeMode
                ccMode = envelopeMode
                dateMode = envelopeMode
            }
            
            if attachmentContentMode == .on && attachmentMetadataMode == .off {
                attachmentContentMode = .off
            }
        }
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        // Encode new mode-based fields
        try c.encode(subjectMode, forKey: .subjectMode)
        try c.encode(fromMode, forKey: .fromMode)
        try c.encode(toMode, forKey: .toMode)
        try c.encode(ccMode, forKey: .ccMode)
        try c.encode(dateMode, forKey: .dateMode)
        try c.encode(bodyMode, forKey: .bodyMode)
        try c.encode(attachmentMetadataMode, forKey: .attachmentMetadataMode)
        try c.encode(attachmentContentMode, forKey: .attachmentContentMode)
        
        // Also encode legacy Bool fields for backward compatibility
        try c.encode(subject, forKey: .subject)
        try c.encode(from, forKey: .from)
        try c.encode(to, forKey: .to)
        try c.encode(cc, forKey: .cc)
        try c.encode(date, forKey: .date)
        try c.encode(body, forKey: .body)
        try c.encode(attachmentMetadata, forKey: .attachmentMetadata)
        try c.encode(attachmentContent, forKey: .attachmentContent)
        try c.encode(envelope, forKey: .envelope)
    }
}

public struct Grant: Equatable, Codable, Sendable {
    public enum Mode: String, Codable, Sendable {
        case allow
        case deny
    }

    public let agentID: String
    public let accountID: String
    /// nil means all placements in the account (snapshot of that account only).
    public let placement: String?
    /// Empty → any participant. Values within this group are OR'd.
    public let participants: [GrantParticipant]
    /// Inclusive lower bound (ISO8601 or RFC2822). nil → open.
    public let dateStart: String?
    /// Inclusive upper bound. nil → open.
    public let dateEnd: String?
    public let mode: Mode
    public let fields: GrantFields

    public init(
        agentID: String,
        accountID: String,
        placement: String? = nil,
        participants: [GrantParticipant] = [],
        dateStart: String? = nil,
        dateEnd: String? = nil,
        mode: Mode = .allow,
        fields: GrantFields = .default
    ) {
        self.agentID = agentID
        self.accountID = accountID
        self.placement = placement
        self.participants = participants.map {
            GrantParticipant(role: $0.role, address: $0.address)
        }
        self.dateStart = dateStart
        self.dateEnd = dateEnd
        self.mode = mode
        self.fields = fields
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        agentID = try c.decode(String.self, forKey: .agentID)
        accountID = try c.decode(String.self, forKey: .accountID)
        placement = try c.decodeIfPresent(String.self, forKey: .placement)
        participants = try c.decodeIfPresent([GrantParticipant].self, forKey: .participants) ?? []
        dateStart = try c.decodeIfPresent(String.self, forKey: .dateStart)
        dateEnd = try c.decodeIfPresent(String.self, forKey: .dateEnd)
        mode = try c.decodeIfPresent(Mode.self, forKey: .mode) ?? .allow
        fields = try c.decodeIfPresent(GrantFields.self, forKey: .fields) ?? .default
    }

    public func matches(
        accountID: String,
        placement: String,
        from: String,
        to: String,
        date: String
    ) -> Bool {
        guard self.accountID == accountID else { return false }
        if let required = self.placement, required != placement { return false }
        if !participants.isEmpty {
            let ok = participants.contains { $0.matches(from: from, to: to) }
            if !ok { return false }
        }
        if dateStart != nil || dateEnd != nil {
            guard let messageDate = Self.parseDate(date) else { return false }
            if let start = dateStart.flatMap(Self.parseDate), messageDate < start { return false }
            if let end = dateEnd.flatMap(Self.parseDate), messageDate > end { return false }
        }
        return true
    }

    /// Placement-only coverage (ignores participant/date — used for listPlacements).
    public func covers(accountID: String, placement: String) -> Bool {
        self.accountID == accountID
            && (self.placement == nil || self.placement == placement)
    }

    static func normalizeAddress(_ raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if let start = trimmed.firstIndex(of: "<"),
           let end = trimmed.firstIndex(of: ">"),
           start < end
        {
            return String(trimmed[trimmed.index(after: start)..<end])
        }
        return trimmed
    }

    static func parseDate(_ raw: String) -> Date? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = iso.date(from: trimmed) { return d }
        iso.formatOptions = [.withInternetDateTime]
        if let d = iso.date(from: trimmed) { return d }
        let rfc = DateFormatter()
        rfc.locale = Locale(identifier: "en_US_POSIX")
        rfc.dateFormat = "EEE, d MMM yyyy HH:mm:ss Z"
        if let d = rfc.date(from: trimmed) { return d }
        rfc.dateFormat = "d MMM yyyy HH:mm:ss Z"
        return rfc.date(from: trimmed)
    }
}

extension GrantParticipant {
    func matches(from: String, to: String) -> Bool {
        let fromAddr = Grant.normalizeAddress(from)
        let toAddr = Grant.normalizeAddress(to)
        switch role {
        case .from:
            return Self.address(fromAddr, matches: address)
        case .to:
            return Self.address(toAddr, matches: address)
        case .anyParticipant:
            return Self.address(fromAddr, matches: address)
                || Self.address(toAddr, matches: address)
        }
    }

    private static func address(_ value: String, matches selector: String) -> Bool {
        if selector.contains("@") {
            return value == selector
        }
        // Domain match: exact host after @
        guard let at = value.firstIndex(of: "@") else { return false }
        let host = String(value[value.index(after: at)...])
        return host == selector
    }
}

/// Codable snapshot for persisting an agent's allows beside pairing.
public struct GrantSnapshot: Equatable, Codable, Sendable {
    public var grants: [Grant]

    public init(grants: [Grant] = []) {
        self.grants = grants
    }
}

public final class GrantGate: @unchecked Sendable {
    private var grants: [Grant] = []
    private let lock = NSLock()

    public init() {}

    public func allow(
        agentID: String,
        accountID: String,
        placement: String? = nil,
        participants: [GrantParticipant] = [],
        dateStart: String? = nil,
        dateEnd: String? = nil,
        fields: GrantFields = .default
    ) throws {
        try upsert(
            Grant(
                agentID: agentID,
                accountID: accountID,
                placement: placement,
                participants: participants,
                dateStart: dateStart,
                dateEnd: dateEnd,
                mode: .allow,
                fields: fields
            )
        )
    }

    public func deny(
        agentID: String,
        accountID: String,
        placement: String? = nil,
        participants: [GrantParticipant] = [],
        dateStart: String? = nil,
        dateEnd: String? = nil
    ) throws {
        try upsert(
            Grant(
                agentID: agentID,
                accountID: accountID,
                placement: placement,
                participants: participants,
                dateStart: dateStart,
                dateEnd: dateEnd,
                mode: .deny,
                fields: .default
            )
        )
    }

    private func upsert(_ grant: Grant) throws {
        lock.lock()
        grants.removeAll {
            $0.agentID == grant.agentID
                && $0.accountID == grant.accountID
                && $0.placement == grant.placement
                && $0.participants == grant.participants
                && $0.dateStart == grant.dateStart
                && $0.dateEnd == grant.dateEnd
                && $0.mode == grant.mode
        }
        grants.append(grant)
        lock.unlock()
    }

    public func list(agentID: String) -> [Grant] {
        lock.lock()
        defer { lock.unlock() }
        return grants.filter { $0.agentID == agentID }
    }

    /// All grants across agents (for union persistence).
    public func allGrants() -> [Grant] {
        lock.lock()
        defer { lock.unlock() }
        return grants
    }

    /// Replaces all grants for `agentID` (used for restore-from-disk). Other agents untouched.
    public func replaceAll(agentID: String, with newGrants: [Grant]) {
        lock.lock()
        grants.removeAll { $0.agentID == agentID }
        grants.append(contentsOf: newGrants.filter { $0.agentID == agentID })
        lock.unlock()
    }

    public func revokeAll(agentID: String) {
        lock.lock()
        grants.removeAll { $0.agentID == agentID }
        lock.unlock()
    }

    public func allows(agentID: String, accountID: String, placement: String) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        let mine = grants.filter { $0.agentID == agentID }
        let allowed = mine.contains {
            $0.mode == .allow && $0.covers(accountID: accountID, placement: placement)
        }
        guard allowed else { return false }
        let denied = mine.contains {
            $0.mode == .deny && $0.covers(accountID: accountID, placement: placement)
        }
        return !denied
    }

    public func allows(_ message: IndexedMessage, agentID: String) -> Bool {
        effectiveFields(for: message, agentID: agentID) != nil
    }

    /// Fields from the first matching allow, if not carved out by a deny. nil → no access.
    public func effectiveFields(for message: IndexedMessage, agentID: String) -> GrantFields? {
        lock.lock()
        defer { lock.unlock() }
        let mine = grants.filter { $0.agentID == agentID }
        let denied = mine.contains {
            $0.mode == .deny
                && $0.matches(
                    accountID: message.accountID,
                    placement: message.placement,
                    from: message.from,
                    to: message.to,
                    date: message.date
                )
        }
        if denied { return nil }
        return mine.first {
            $0.mode == .allow
                && $0.matches(
                    accountID: message.accountID,
                    placement: message.placement,
                    from: message.from,
                    to: message.to,
                    date: message.date
                )
        }?.fields
    }

    public func filter(_ messages: [IndexedMessage], agentID: String) -> [IndexedMessage] {
        messages.filter { allows($0, agentID: agentID) }
    }

    public func filter(_ placements: [Placement], agentID: String) -> [Placement] {
        placements.filter { allows(agentID: agentID, accountID: $0.accountID, placement: $0.id) }
    }
}
