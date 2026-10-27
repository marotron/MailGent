import Foundation
import MailStore

enum MailGentPreferences {
    static let agentMayChangeSourceKey = "agentMayChangeSource"
    static let agentMayOpenInMailKey = "agentMayOpenInMail"
    static let loopbackPortKey = "loopbackPort"
    static let auditMaxAgeSecondsKey = "auditMaxAgeSeconds"
    static let auditMaxCountKey = "auditMaxCount"
    static let auditMaxBytesKey = "auditMaxBytes"
    /// When on, Grant Desk field chips may use Ask and MCP get may prompt. Off by default.
    static let allowConditionalAccessPromptsKey = "allowConditionalAccessPrompts"
    /// When on (and conditional prompts are allowed), remember Ask Allow/Block per field for a short window.
    static let askDecisionCacheEnabledKey = "askDecisionCacheEnabled"
    /// Wall-clock TTL in seconds. `0` → until MailGent quits (memory only). `-1` → forever (disk).
    static let askDecisionCacheTTLSecondsKey = "askDecisionCacheTTLSeconds"
    /// `perAgent` (default) or `allAgents`.
    static let askDecisionCacheShareScopeKey = "askDecisionCacheShareScope"

    static let defaultLoopbackPort: UInt16 = 8788
    /// Default TTL when the cache is first enabled in Settings (1 hour).
    static let defaultAskDecisionCacheTTLSeconds = 3_600
    /// UserDefaults tag for forever (no wall-clock expiry; persisted).
    static let askDecisionCacheTTLForever = -1

    static var agentMayChangeSource: Bool {
        UserDefaults.standard.bool(forKey: agentMayChangeSourceKey)
    }

    static var agentMayOpenInMail: Bool {
        UserDefaults.standard.bool(forKey: agentMayOpenInMailKey)
    }

    static var allowConditionalAccessPrompts: Bool {
        UserDefaults.standard.bool(forKey: allowConditionalAccessPromptsKey)
    }

    static var askDecisionCacheEnabled: Bool {
        UserDefaults.standard.bool(forKey: askDecisionCacheEnabledKey)
    }

    static var askDecisionCacheShareScope: AskDecisionCacheShareScope {
        let raw = UserDefaults.standard.string(forKey: askDecisionCacheShareScopeKey) ?? ""
        return AskDecisionCacheShareScope(rawValue: raw) ?? .perAgent
    }

    static var askDecisionCachePolicy: AskDecisionCachePolicy {
        let enabled = askDecisionCacheEnabled
        let shareScope = askDecisionCacheShareScope
        guard UserDefaults.standard.object(forKey: askDecisionCacheTTLSecondsKey) != nil else {
            return AskDecisionCachePolicy(
                enabled: enabled,
                ttlSeconds: TimeInterval(defaultAskDecisionCacheTTLSeconds),
                persistAcrossLaunches: true,
                shareScope: shareScope
            )
        }
        let value = UserDefaults.standard.integer(forKey: askDecisionCacheTTLSecondsKey)
        if value < 0 {
            return AskDecisionCachePolicy(
                enabled: enabled,
                ttlSeconds: nil,
                persistAcrossLaunches: true,
                shareScope: shareScope
            )
        }
        if value == 0 {
            return AskDecisionCachePolicy(
                enabled: enabled,
                ttlSeconds: nil,
                persistAcrossLaunches: false,
                shareScope: shareScope
            )
        }
        return AskDecisionCachePolicy(
            enabled: enabled,
            ttlSeconds: TimeInterval(value),
            persistAcrossLaunches: true,
            shareScope: shareScope
        )
    }

    static var loopbackPort: UInt16 {
        normalizedLoopbackPort(UserDefaults.standard.integer(forKey: loopbackPortKey))
    }

    static var loopbackURL: String {
        "http://127.0.0.1:\(loopbackPort)/mcp"
    }

    static func normalizedLoopbackPort(_ value: Int) -> UInt16 {
        guard value >= 1, value <= 65_535 else { return defaultLoopbackPort }
        return UInt16(value)
    }

    static var auditRetention: AuditRetention {
        AuditRetention(
            maxAge: positiveSeconds(auditMaxAgeSecondsKey),
            maxCount: positiveInt(auditMaxCountKey),
            maxBytes: positiveInt(auditMaxBytesKey)
        )
    }

    private static func positiveInt(_ key: String) -> Int? {
        let value = UserDefaults.standard.integer(forKey: key)
        return value > 0 ? value : nil
    }

    private static func positiveSeconds(_ key: String) -> TimeInterval? {
        positiveInt(key).map(TimeInterval.init)
    }
}
