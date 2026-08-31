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
