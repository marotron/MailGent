import Foundation
import MailStore

enum MailGentPreferences {
    static let agentMayChangeSourceKey = "agentMayChangeSource"
    static let agentMayOpenInMailKey = "agentMayOpenInMail"
    static let agentMayProposeSendKey = "agentMayProposeSend"
    /// Hard wait for a pending `propose_send` before expiry (no auto-send). Seconds.
    static let proposeSendHardTimeoutSecondsKey = "proposeSendHardTimeoutSeconds"
    /// When on, `list_accounts` includes identities with empty placements (off by default).
    static let revealAccountsWithNoPlacementsKey = "revealAccountsWithNoPlacements"
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
    /// Experimental: show Assembly-C context thread on `propose_send` when agent sends `context`.
    static let proposeSendContextExperimentalKey = "proposeSendContextExperimental"
    /// Security-scoped bookmark data for Personal vault root (used by experimental context resolve).
    static let personalVaultRootBookmarkKey = "personalVaultRootBookmark"
    /// Master toggle for secret constants (MCP `list_secrets`, placeholders, resolve, value leak hits).
    static let secretConstantsEnabledKey = "secretConstantsEnabled"
    /// When on, soft `await_propose_send` `awaiting_user` polls appear in Access log (default off).
    static let logAwaitProposeSendSoftWaitsKey = "logAwaitProposeSendSoftWaits"

    static let defaultLoopbackPort: UInt16 = 8788
    /// Default TTL when the cache is first enabled in Settings (1 hour).
    static let defaultAskDecisionCacheTTLSeconds = 3_600
    /// Default hard wait for propose_send confirmation (1 hour).
    static let defaultProposeSendHardTimeoutSeconds = 3_600
    static let proposeSendHardTimeoutMinSeconds = 300
    static let proposeSendHardTimeoutMaxSeconds = 28_800
    /// UserDefaults tag for forever (no wall-clock expiry; persisted).
    static let askDecisionCacheTTLForever = -1

    static var agentMayChangeSource: Bool {
        UserDefaults.standard.bool(forKey: agentMayChangeSourceKey)
    }

    static var agentMayOpenInMail: Bool {
        UserDefaults.standard.bool(forKey: agentMayOpenInMailKey)
    }

    static var agentMayProposeSend: Bool {
        UserDefaults.standard.bool(forKey: agentMayProposeSendKey)
    }

    static var proposeSendHardTimeoutSeconds: Int {
        let raw: Int
        if UserDefaults.standard.object(forKey: proposeSendHardTimeoutSecondsKey) == nil {
            raw = defaultProposeSendHardTimeoutSeconds
        } else {
            raw = UserDefaults.standard.integer(forKey: proposeSendHardTimeoutSecondsKey)
        }
        return clampProposeSendHardTimeoutSeconds(raw)
    }

    static func clampProposeSendHardTimeoutSeconds(_ value: Int) -> Int {
        min(max(value, proposeSendHardTimeoutMinSeconds), proposeSendHardTimeoutMaxSeconds)
    }

    static var proposeSendContextExperimental: Bool {
        UserDefaults.standard.bool(forKey: proposeSendContextExperimentalKey)
    }

    static var secretConstantsEnabled: Bool {
        UserDefaults.standard.bool(forKey: secretConstantsEnabledKey)
    }

    static var logAwaitProposeSendSoftWaits: Bool {
        UserDefaults.standard.bool(forKey: logAwaitProposeSendSoftWaitsKey)
    }

    static var revealAccountsWithNoPlacements: Bool {
        UserDefaults.standard.bool(forKey: revealAccountsWithNoPlacementsKey)
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
