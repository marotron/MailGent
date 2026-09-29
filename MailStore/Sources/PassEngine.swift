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

public struct MatchRule: Equatable, Codable, Sendable {
    public var value: String
    public var mode: MatchMode

    public init(value: String, mode: MatchMode) {
        self.value = value
        self.mode = mode
    }
}

public struct Pass: Identifiable, Equatable, Codable, Sendable {
    public var id: String
    public var name: String
    public var nick: String
    public var fromRules: [MatchRule]
    public var subjectRules: [MatchRule]
    public var betweenJoin: JoinOp
    public var fields: GrantFields
    public var agentIDs: [String]

    public init(
        id: String,
        name: String,
        nick: String,
        fromRules: [MatchRule] = [],
        subjectRules: [MatchRule] = [],
        betweenJoin: JoinOp = .and,
        fields: GrantFields,
        agentIDs: [String]
    ) {
        self.id = id
        self.name = name
        self.nick = nick
        self.fromRules = fromRules
        self.subjectRules = subjectRules
        self.betweenJoin = betweenJoin
        self.fields = fields
        self.agentIDs = agentIDs
    }
}

public struct PassEnablement: Equatable, Codable, Sendable {
    public var passID: String
    public var accountID: String
    public var placement: String?

    public init(passID: String, accountID: String, placement: String? = nil) {
        self.passID = passID
        self.accountID = accountID
        self.placement = placement
    }
}

public enum PassEngine {
    /// Unions matching enabled pass fields onto an already-allowed base. Does not grant access.
    public static func upgrade(
        base: GrantFields,
        message: IndexedMessage,
        agentID: String,
        passes: [Pass],
        enablements: [PassEnablement]
    ) -> GrantFields {
        var result = base
        for pass in passes where applies(pass, to: message, agentID: agentID, enablements: enablements) {
            result = result.unioning(pass.fields)
        }
        return result
    }

    private static func applies(
        _ pass: Pass,
        to message: IndexedMessage,
        agentID: String,
        enablements: [PassEnablement]
    ) -> Bool {
        guard pass.agentIDs.contains(agentID) else { return false }
        guard isEnabled(passID: pass.id, message: message, enablements: enablements) else { return false }
        return matches(pass, message: message)
    }

    private static func isEnabled(
        passID: String,
        message: IndexedMessage,
        enablements: [PassEnablement]
    ) -> Bool {
        enablements.contains {
            $0.passID == passID
                && $0.accountID == message.accountID
                && ($0.placement == nil || $0.placement == message.placement)
        }
    }

    private static func matches(_ pass: Pass, message: IndexedMessage) -> Bool {
        let fromActive = !pass.fromRules.isEmpty
        let subjectActive = !pass.subjectRules.isEmpty
        // Incomplete pass: no rules yet → never fire (would otherwise match everything).
        guard fromActive || subjectActive else { return false }

        let fromOK = groupMatches(pass.fromRules, haystack: message.from)
        let subjectOK = groupMatches(pass.subjectRules, haystack: message.subject)
        switch pass.betweenJoin {
        case .and:
            return fromOK && subjectOK
        case .or:
            if fromActive && subjectActive { return fromOK || subjectOK }
            return fromActive ? fromOK : subjectOK
        }
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
}
