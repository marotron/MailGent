import Foundation

/// Hard-timeout countdown copy for the propose-send confirm dialog.
public enum ProposeSendExpiryFormat {
    /// `Expires in H:MM:SS` when ≥ 1 hour, otherwise `Expires in M:SS`.
    public static func countdownLabel(remaining: TimeInterval) -> String {
        let total = max(0, Int(remaining.rounded(.down)))
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        let seconds = total % 60
        let clock: String
        if hours > 0 {
            clock = String(format: "%d:%02d:%02d", hours, minutes, seconds)
        } else {
            clock = String(format: "%d:%02d", minutes, seconds)
        }
        return "Expires in \(clock)"
    }
}
