import Foundation

enum MailGentPreferences {
    static let agentMayChangeSourceKey = "agentMayChangeSource"

    static var agentMayChangeSource: Bool {
        UserDefaults.standard.bool(forKey: agentMayChangeSourceKey)
    }
}
