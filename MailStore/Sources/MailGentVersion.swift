import Foundation

/// Single source for SemVer marketing + release-candidate identity.
/// Keep in sync with `project.yml` (`MARKETING_VERSION`, `INFOPLIST_KEY_MailGentReleaseCandidate`).
public enum MailGentVersion {
    /// Apple `CFBundleShortVersionString` — three period-separated integers only.
    public static let marketing = "0.25.2"

    /// `0` = shipped marketing line; `N > 0` → SemVer pre-release `marketing-rc.N`.
    public static let releaseCandidate = 7

    /// Display / MCP label: `0.24.1` or `0.24.1-rc.1`.
    public static var label: String {
        Self.label(marketing: marketing, releaseCandidate: releaseCandidate)
    }

    public static func label(marketing: String, releaseCandidate: Int) -> String {
        if releaseCandidate > 0 {
            return "\(marketing)-rc.\(releaseCandidate)"
        }
        return marketing
    }

    public static var isCandidate: Bool { releaseCandidate > 0 }
}
