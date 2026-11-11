import Foundation

/// Ask-window caption when Settings → Remember Ask decisions is on.
public enum AskRememberCaption {
    /// e.g. `Remember for 30 days (this agent)` — checkbox label; `nil` when Settings is off.
    public static func note(for policy: AskDecisionCachePolicy) -> String? {
        guard policy.enabled else { return nil }
        let duration = durationLabel(ttlSeconds: policy.ttlSeconds, persist: policy.persistAcrossLaunches)
        let scope = shareLabel(policy.shareScope)
        return "Remember for \(duration) (\(scope))"
    }

    /// Write Remember only when Settings is on **and** this Ask’s checkbox stayed checked.
    public static func shouldWrite(
        policy: AskDecisionCachePolicy,
        rememberThisDecision: Bool
    ) -> Bool {
        policy.enabled && rememberThisDecision
    }

    public static func durationLabel(ttlSeconds: TimeInterval?, persist: Bool) -> String {
        guard let ttl = ttlSeconds else {
            return persist ? "Forever" : "Until MailGent quits"
        }
        switch Int(ttl) {
        case 900: return "15 minutes"
        case 3_600: return "1 hour"
        case 86_400: return "24 hours"
        case 2_592_000: return "30 days"
        case 31_536_000: return "1 year"
        default:
            if ttl < 60 { return "\(Int(ttl)) seconds" }
            if ttl < 3_600 {
                let minutes = Int(ttl / 60)
                return minutes == 1 ? "1 minute" : "\(minutes) minutes"
            }
            if ttl < 86_400 {
                let hours = Int(ttl / 3_600)
                return hours == 1 ? "1 hour" : "\(hours) hours"
            }
            let days = Int(ttl / 86_400)
            return days == 1 ? "1 day" : "\(days) days"
        }
    }

    public static func shareLabel(_ scope: AskDecisionCacheShareScope) -> String {
        switch scope {
        case .perAgent: "this agent"
        case .allAgents: "all agents"
        }
    }
}
