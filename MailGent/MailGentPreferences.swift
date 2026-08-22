import Foundation
import MailStore

enum MailGentPreferences {
    static let agentMayChangeSourceKey = "agentMayChangeSource"
    static let auditMaxAgeSecondsKey = "auditMaxAgeSeconds"
    static let auditMaxCountKey = "auditMaxCount"
    static let auditMaxBytesKey = "auditMaxBytes"

    static var agentMayChangeSource: Bool {
        UserDefaults.standard.bool(forKey: agentMayChangeSourceKey)
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
