import Foundation

public enum BuiltInLeakClass: String, Codable, CaseIterable, Sendable {
    case apiKeys
    case jwt
    case privateKeys
    case passwordCtx
    case creditCards
    case ssn
    case phones
    case emails
}

public enum LeakGuardHitMode: String, Codable, Sendable {
    case redactSpans
    case blockWhole
}

public struct CustomLeakRule: Equatable, Codable, Identifiable, Sendable {
    public enum Kind: String, Codable, Sendable {
        case literal
        case wildcard
        case regex
    }

    public enum Action: String, Codable, Sendable {
        case redact
        case replace
    }

    public let id: String
    public var label: String
    public var kind: Kind
    public var pattern: String
    public var caseInsensitive: Bool
    public var action: Action
    public var actionValue: String
    public var discloseToAgent: Bool
    public var enabled: Bool

    public init(
        id: String = UUID().uuidString,
        label: String,
        kind: Kind,
        pattern: String,
        caseInsensitive: Bool = false,
        action: Action,
        actionValue: String,
        discloseToAgent: Bool = true,
        enabled: Bool = true
    ) {
        self.id = id
        self.label = label
        self.kind = kind
        self.pattern = pattern
        self.caseInsensitive = caseInsensitive
        self.action = action
        self.actionValue = actionValue
        self.discloseToAgent = discloseToAgent
        self.enabled = enabled
    }

    /// Returns nil when valid; otherwise a human-readable rejection reason.
    public static func validatePattern(kind: Kind, pattern: String) -> String? {
        let trimmed = pattern.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "Pattern cannot be empty." }
        switch kind {
        case .literal, .wildcard:
            return nil
        case .regex:
            do {
                _ = try NSRegularExpression(pattern: trimmed)
                return nil
            } catch {
                return "Invalid regular expression."
            }
        }
    }
}

public struct OutboundLeakGuardPolicy: Equatable, Codable, Sendable {
    public var enabled: Bool
    /// Keys: `accountID/placement` or `accountID/*` for account-wide opt-in.
    public var scopes: Set<String>
    public var builtInClasses: [BuiltInLeakClass: Bool]
    public var customRules: [CustomLeakRule]
    public var subjectHitMode: LeakGuardHitMode
    public var bodyHitMode: LeakGuardHitMode

    public init(
        enabled: Bool = false,
        scopes: Set<String> = [],
        builtInClasses: [BuiltInLeakClass: Bool]? = nil,
        customRules: [CustomLeakRule] = [],
        subjectHitMode: LeakGuardHitMode = .redactSpans,
        bodyHitMode: LeakGuardHitMode = .redactSpans
    ) {
        self.enabled = enabled
        self.scopes = scopes
        self.builtInClasses = builtInClasses ?? Self.defaultBuiltInClasses
        self.customRules = customRules
        self.subjectHitMode = subjectHitMode
        self.bodyHitMode = bodyHitMode
    }

    public static let `default` = OutboundLeakGuardPolicy()

    public static var defaultBuiltInClasses: [BuiltInLeakClass: Bool] {
        var map = Dictionary(uniqueKeysWithValues: BuiltInLeakClass.allCases.map { ($0, false) })
        map[.apiKeys] = true
        map[.jwt] = true
        map[.passwordCtx] = true
        return map
    }

    public static func scopeKey(accountID: String, placement: String?) -> String {
        if let placement {
            return "\(accountID)/\(placement)"
        }
        return "\(accountID)/*"
    }

    public func isScopeProtected(accountID: String, placement: String) -> Bool {
        guard enabled, !scopes.isEmpty else { return false }
        let exact = Self.scopeKey(accountID: accountID, placement: placement)
        if scopes.contains(exact) { return true }
        return scopes.contains(Self.scopeKey(accountID: accountID, placement: nil))
    }
}

extension OutboundLeakGuardPolicy {
    enum CodingKeys: String, CodingKey {
        case enabled, scopes, builtInClasses, customRules, subjectHitMode, bodyHitMode
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        enabled = try c.decodeIfPresent(Bool.self, forKey: .enabled) ?? false
        scopes = try c.decodeIfPresent(Set<String>.self, forKey: .scopes) ?? []
        if let rawBuiltIns = try c.decodeIfPresent([String: Bool].self, forKey: .builtInClasses) {
            var map = Self.defaultBuiltInClasses
            for (key, value) in rawBuiltIns {
                if let cls = BuiltInLeakClass(rawValue: key) {
                    map[cls] = value
                }
            }
            builtInClasses = map
        } else {
            builtInClasses = Self.defaultBuiltInClasses
        }
        customRules = try c.decodeIfPresent([CustomLeakRule].self, forKey: .customRules) ?? []
        subjectHitMode = try c.decodeIfPresent(LeakGuardHitMode.self, forKey: .subjectHitMode) ?? .redactSpans
        bodyHitMode = try c.decodeIfPresent(LeakGuardHitMode.self, forKey: .bodyHitMode) ?? .redactSpans
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(enabled, forKey: .enabled)
        try c.encode(scopes, forKey: .scopes)
        let rawBuiltIns = Dictionary(uniqueKeysWithValues: builtInClasses.map { ($0.key.rawValue, $0.value) })
        try c.encode(rawBuiltIns, forKey: .builtInClasses)
        try c.encode(customRules, forKey: .customRules)
        try c.encode(subjectHitMode, forKey: .subjectHitMode)
        try c.encode(bodyHitMode, forKey: .bodyHitMode)
    }
}
