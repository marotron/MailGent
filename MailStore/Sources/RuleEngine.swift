import Foundation

public enum MatchMode: String, Codable, Sendable {
    case contains
    case starts
    case ends
    case exact
}

public enum JoinOp: String, Codable, Sendable {
    case and
    case or
}

/// Pass = potential grant overwrite; Block = potential deny overwrite.
public enum RulePolarity: String, Codable, Sendable {
    case pass
    case block
}

public struct MatchRule: Equatable, Codable, Sendable {
    public var value: String
    public var mode: MatchMode

    public init(value: String, mode: MatchMode) {
        self.value = value
        self.mode = mode
    }
}

/// Optional received-date window. Presence means When is on; empty side = open-ended.
public struct RuleWhen: Equatable, Codable, Sendable {
    public var after: String?
    public var before: String?

    public init(after: String? = nil, before: String? = nil) {
        self.after = after
        self.before = before
    }
}

/// Field overlay on Scope-allowed messages: Pass grants denied fields; Block denies granted fields.
public struct GrantRule: Identifiable, Equatable, Codable, Sendable {
    public var id: String
    public var name: String
    public var nick: String
    public var polarity: RulePolarity
    public var fromRules: [MatchRule]
    public var subjectRules: [MatchRule]
    public var betweenJoin: JoinOp
    public var when: RuleWhen?
    public var whenJoin: JoinOp
    public var fields: GrantFields

    public init(
        id: String,
        name: String,
        nick: String,
        polarity: RulePolarity = .pass,
        fromRules: [MatchRule] = [],
        subjectRules: [MatchRule] = [],
        betweenJoin: JoinOp = .and,
        when: RuleWhen? = nil,
        whenJoin: JoinOp = .and,
        fields: GrantFields
    ) {
        self.id = id
        self.name = name
        self.nick = nick
        self.polarity = polarity
        self.fromRules = fromRules
        self.subjectRules = subjectRules
        self.betweenJoin = betweenJoin
        self.when = when
        self.whenJoin = whenJoin
        self.fields = fields
    }
}

public struct RuleEnablement: Equatable, Codable, Sendable {
    public var ruleID: String
    /// Agent this enablement applies to. Empty = legacy shared (matches any agent until migrated).
    public var agentID: String
    public var accountID: String
    public var placement: String?

    public init(ruleID: String, agentID: String, accountID: String, placement: String? = nil) {
        self.ruleID = ruleID
        self.agentID = agentID
        self.accountID = accountID
        self.placement = placement
    }

    enum CodingKeys: String, CodingKey {
        case ruleID, agentID, accountID, placement
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        ruleID = try c.decode(String.self, forKey: .ruleID)
        agentID = try c.decodeIfPresent(String.self, forKey: .agentID) ?? ""
        accountID = try c.decode(String.self, forKey: .accountID)
        placement = try c.decodeIfPresent(String.self, forKey: .placement)
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(ruleID, forKey: .ruleID)
        try c.encode(agentID, forKey: .agentID)
        try c.encode(accountID, forKey: .accountID)
        try c.encodeIfPresent(placement, forKey: .placement)
    }
}

/// Rule that actually changed grant fields when applied (Pass grant / Block deny overwrite).
public struct AppliedGrantRule: Equatable, Hashable, Codable, Sendable {
    public var id: String
    public var nick: String
    public var polarity: RulePolarity
    /// Fields this application changed (Pass: newly granted; Block: newly denied).
    public var fields: GrantFields

    public init(
        id: String,
        nick: String,
        polarity: RulePolarity,
        fields: GrantFields = .none
    ) {
        self.id = id
        self.nick = nick
        self.polarity = polarity
        self.fields = fields
    }

    enum CodingKeys: String, CodingKey {
        case id, nick, polarity, fields
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        nick = try c.decode(String.self, forKey: .nick)
        polarity = try c.decode(RulePolarity.self, forKey: .polarity)
        fields = try c.decodeIfPresent(GrantFields.self, forKey: .fields) ?? .none
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(nick, forKey: .nick)
        try c.encode(polarity, forKey: .polarity)
        try c.encode(fields, forKey: .fields)
    }
}

public enum RuleEngine {
    /// Field overlays on a Scope-allowed base: Pass grant-overwrite (union), then Block deny-overwrite (subtract).
    /// Irrelevant when a Pass field is already on, or a Block field is already off. Never opens a closed Scope gate.
    public static func applyOverlays(
        base: GrantFields,
        message: IndexedMessage,
        agentID: String,
        rules: [GrantRule],
        enablements: [RuleEnablement]
    ) -> GrantFields {
        applyOverlaysWithApplied(
            base: base,
            message: message,
            agentID: agentID,
            rules: rules,
            enablements: enablements
        ).fields
    }

    /// Same as `applyOverlays`, plus rules that changed fields (match with no delta is omitted).
    public static func applyOverlaysWithApplied(
        base: GrantFields,
        message: IndexedMessage,
        agentID: String,
        rules: [GrantRule],
        enablements: [RuleEnablement]
    ) -> (fields: GrantFields, applied: [AppliedGrantRule]) {
        let matching = rules.filter { applies($0, to: message, agentID: agentID, enablements: enablements) }
        var result = base
        var applied: [AppliedGrantRule] = []
        for rule in matching where rule.polarity == .pass {
            let next = result.unioning(rule.fields)
            if next != result {
                applied.append(
                    AppliedGrantRule(
                        id: rule.id,
                        nick: rule.nick,
                        polarity: .pass,
                        fields: next.bitsNotIn(result)
                    )
                )
                result = next
            }
        }
        for rule in matching where rule.polarity == .block {
            let next = result.subtracting(rule.fields)
            if next != result {
                applied.append(
                    AppliedGrantRule(
                        id: rule.id,
                        nick: rule.nick,
                        polarity: .block,
                        fields: result.bitsNotIn(next)
                    )
                )
                result = next
            }
        }
        return (result, applied)
    }

    /// Whether a rule matches (per-agent enablement + matchers/When), ignoring polarity effect.
    public static func matches(
        _ rule: GrantRule,
        message: IndexedMessage,
        agentID: String,
        enablements: [RuleEnablement]
    ) -> Bool {
        applies(rule, to: message, agentID: agentID, enablements: enablements)
    }

    private static func applies(
        _ rule: GrantRule,
        to message: IndexedMessage,
        agentID: String,
        enablements: [RuleEnablement]
    ) -> Bool {
        guard isEnabled(ruleID: rule.id, agentID: agentID, message: message, enablements: enablements) else {
            return false
        }
        return matchesMatchers(rule, message: message)
    }

    private static func isEnabled(
        ruleID: String,
        agentID: String,
        message: IndexedMessage,
        enablements: [RuleEnablement]
    ) -> Bool {
        enablements.contains {
            $0.ruleID == ruleID
                && ($0.agentID.isEmpty || $0.agentID == agentID)
                && $0.accountID == message.accountID
                && ($0.placement == nil || $0.placement == message.placement)
        }
    }

    private static func matchesMatchers(_ rule: GrantRule, message: IndexedMessage) -> Bool {
        let fromActive = !rule.fromRules.isEmpty
        let subjectActive = !rule.subjectRules.isEmpty
        let matcherActive = fromActive || subjectActive
        let whenActive = rule.when != nil
        // Incomplete rule: nothing to match → never fire.
        guard matcherActive || whenActive else { return false }

        let matcherOK: Bool = {
            guard matcherActive else { return true }
            // From matchers use the mailbox address (`Name <addr@host>` → `addr@host`).
            let fromOK = groupMatches(rule.fromRules, haystack: Grant.normalizeAddress(message.from))
            let subjectOK = groupMatches(rule.subjectRules, haystack: message.subject)
            switch rule.betweenJoin {
            case .and:
                return fromOK && subjectOK
            case .or:
                if fromActive && subjectActive { return fromOK || subjectOK }
                return fromActive ? fromOK : subjectOK
            }
        }()

        let whenOK: Bool = {
            guard let when = rule.when else { return true }
            return whenMatches(when, messageDate: message.date)
        }()

        if matcherActive && whenActive {
            switch rule.whenJoin {
            case .and: return matcherOK && whenOK
            case .or: return matcherOK || whenOK
            }
        }
        return matcherActive ? matcherOK : whenOK
    }

    /// Empty rules → ignore group (vacuous true). Non-empty → any rule (OR).
    private static func groupMatches(_ rules: [MatchRule], haystack: String) -> Bool {
        guard !rules.isEmpty else { return true }
        return rules.contains { ruleMatches($0, haystack: haystack) }
    }

    private static func ruleMatches(_ rule: MatchRule, haystack: String) -> Bool {
        let needle = rule.value
        guard !needle.isEmpty else { return false }
        let hay = haystack
        switch rule.mode {
        case .contains:
            return hay.range(of: needle, options: .caseInsensitive) != nil
        case .starts:
            return hay.range(of: needle, options: [.caseInsensitive, .anchored]) != nil
        case .ends:
            guard hay.count >= needle.count else { return false }
            let start = hay.index(hay.endIndex, offsetBy: -needle.count)
            return hay[start...].range(of: needle, options: .caseInsensitive) != nil
        case .exact:
            return hay.caseInsensitiveCompare(needle) == .orderedSame
        }
    }

    /// Inclusive day window. `after` / `before` are `YYYY-MM-DD` (or fuller ISO8601); message date is ISO8601.
    private static func whenMatches(_ when: RuleWhen, messageDate: String) -> Bool {
        guard let messageInstant = parseInstant(messageDate) else { return false }
        if let after = when.after?.trimmingCharacters(in: .whitespacesAndNewlines), !after.isEmpty {
            guard let start = parseDayBound(after, endOfDay: false), messageInstant >= start else { return false }
        }
        if let before = when.before?.trimmingCharacters(in: .whitespacesAndNewlines), !before.isEmpty {
            guard let end = parseDayBound(before, endOfDay: true), messageInstant <= end else { return false }
        }
        return true
    }

    private static func parseInstant(_ raw: String) -> Date? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = iso.date(from: trimmed) { return d }
        iso.formatOptions = [.withInternetDateTime]
        if let d = iso.date(from: trimmed) { return d }
        return parseDayBound(trimmed, endOfDay: false)
    }

    private static func parseDayBound(_ raw: String, endOfDay: Bool) -> Date? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        let day = String(trimmed.prefix(10))
        let parts = day.split(separator: "-")
        guard parts.count == 3,
              let y = Int(parts[0]), let m = Int(parts[1]), let d = Int(parts[2]),
              let date = Calendar(identifier: .gregorian).date(from: DateComponents(
                  timeZone: TimeZone(secondsFromGMT: 0),
                  year: y, month: m, day: d,
                  hour: endOfDay ? 23 : 0,
                  minute: endOfDay ? 59 : 0,
                  second: endOfDay ? 59 : 0
              ))
        else { return nil }
        return date
    }
}

extension GrantFields {
    /// Field-wise OR. Attachment content still requires metadata.
    public func unioning(_ other: GrantFields) -> GrantFields {
        GrantFields(
            subject: subject || other.subject,
            from: from || other.from,
            to: to || other.to,
            cc: cc || other.cc,
            date: date || other.date,
            body: body || other.body,
            attachmentMetadata: attachmentMetadata || other.attachmentMetadata,
            attachmentContent: attachmentContent || other.attachmentContent
        )
    }

    /// Field-wise AND-NOT for Blocks. Clearing metadata also clears content.
    public func subtracting(_ other: GrantFields) -> GrantFields {
        var next = GrantFields(
            subject: subject && !other.subject,
            from: from && !other.from,
            to: to && !other.to,
            cc: cc && !other.cc,
            date: date && !other.date,
            body: body && !other.body,
            attachmentMetadata: attachmentMetadata && !other.attachmentMetadata,
            attachmentContent: attachmentContent && !other.attachmentContent
        )
        if !next.attachmentMetadata {
            next.attachmentContent = false
        }
        return next
    }
}
