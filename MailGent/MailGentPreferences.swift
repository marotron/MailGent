import Foundation
import MailStore

enum MailGentPreferences {
    static let agentMayChangeSourceKey = "agentMayChangeSource"
    static let loopbackPortKey = "loopbackPort"
    static let auditMaxAgeSecondsKey = "auditMaxAgeSeconds"
    static let auditMaxCountKey = "auditMaxCount"
    static let auditMaxBytesKey = "auditMaxBytes"

    static let defaultLoopbackPort: UInt16 = 8788

    static var agentMayChangeSource: Bool {
        UserDefaults.standard.bool(forKey: agentMayChangeSourceKey)
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
