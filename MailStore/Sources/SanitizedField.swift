import Foundation

public enum FieldAccess: String, Codable, Sendable {
    case granted
    case notGranted = "not_granted"
    case sanitized
    case withheldConfidential = "withheld_confidential"
}

public enum FieldAccessReason: String, Codable, Sendable {
    case grant
    case leakGuard = "leak_guard"
    /// User Allowed an Ask (conditional) prompt for this field on this get.
    case conditional
    /// User Blocked an Ask (conditional) prompt for this field on this get.
    case conditionalBlocked = "conditional_blocked"
}

extension SanitizedField {
    /// Stamp Ask prompt outcome without overriding leak-guard classifications.
    public func markingConditionalPrompt(allowed: Bool) -> SanitizedField {
        guard reason != .leakGuard else { return self }
        return SanitizedField(
            text: text,
            access: access,
            agentAccess: agentAccess,
            reason: allowed ? .conditional : .conditionalBlocked,
            disclosedRules: disclosedRules,
            allRules: allRules,
            original: original,
            hitSpans: hitSpans,
            stealth: stealth
        )
    }
}

public struct LeakHitSpan: Equatable, Sendable {
    public let start: Int
    public let end: Int
    public let label: String
    public let source: String
    public let action: CustomLeakRule.Action
    public let actionValue: String
    public let discloseToAgent: Bool

    public var length: Int { end - start }
}

public struct SanitizedField: Equatable, Sendable {
    /// Text returned to the agent.
    public let text: String
    /// Human / audit access classification.
    public let access: FieldAccess
    /// MCP-facing access flag.
    public let agentAccess: FieldAccess
    public let reason: FieldAccessReason?
    /// Rule labels disclosed to the agent (`sanitizedRules` in MCP JSON).
    public let disclosedRules: [String]
    /// All rule labels that matched (audit).
    public let allRules: [String]
    public let original: String
    public let hitSpans: [LeakHitSpan]
    /// True when replace rules hide sanitization from the agent.
    public let stealth: Bool

    public static func notGranted(original: String) -> SanitizedField {
        SanitizedField(
            text: "",
            access: .notGranted,
            agentAccess: .notGranted,
            reason: .grant,
            disclosedRules: [],
            allRules: [],
            original: original,
            hitSpans: [],
            stealth: false
        )
    }

    public static func granted(_ text: String, original: String? = nil) -> SanitizedField {
        SanitizedField(
            text: text,
            access: .granted,
            agentAccess: .granted,
            reason: .grant,
            disclosedRules: [],
            allRules: [],
            original: original ?? text,
            hitSpans: [],
            stealth: false
        )
    }
}

extension FieldAccess {
    public var auditBodyAccess: AuditBodyAccess {
        switch self {
        case .granted: .granted
        case .notGranted: .notGranted
        case .sanitized: .sanitized
        case .withheldConfidential: .withheldConfidential
        }
    }
}

public struct ReadMessageAccess: Equatable, Sendable {
    public let subjectAccess: FieldAccess
    public let bodyAccess: FieldAccess
    public let subjectAccessReason: FieldAccessReason?
    public let bodyAccessReason: FieldAccessReason?
    public let sanitizedRules: [String]
    public let subjectOriginal: String?
    public let bodyOriginal: String?
    public let stealth: Bool
    /// Field labels the user Allowed on an Ask prompt for this get (e.g. `Body`).
    public let conditionalAccessFields: [String]
    /// Field labels the user Blocked on an Ask prompt for this get (e.g. `Body`).
    public let conditionalBlockedFields: [String]

    public init(
        subject: SanitizedField,
        body: SanitizedField,
        conditionalAccessFields: [String] = [],
        conditionalBlockedFields: [String] = []
    ) {
        subjectAccess = subject.agentAccess
        bodyAccess = body.agentAccess
        subjectAccessReason = subject.reason
        bodyAccessReason = body.reason
        sanitizedRules = Array(Set(subject.disclosedRules + body.disclosedRules)).sorted()
        subjectOriginal = subject.original != subject.text ? subject.original : nil
        bodyOriginal = body.original != body.text ? body.original : nil
        stealth = subject.stealth || body.stealth
        self.conditionalAccessFields = conditionalAccessFields
        self.conditionalBlockedFields = conditionalBlockedFields
    }
}
