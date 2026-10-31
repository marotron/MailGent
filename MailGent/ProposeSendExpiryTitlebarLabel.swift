import MailStore
import SwiftUI

/// Titlebar-trailing hard-timeout countdown for propose-send confirm.
struct ProposeSendExpiryTitlebarLabel: View {
    let expiresAt: Date

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let remaining = expiresAt.timeIntervalSince(context.date)
            let label = ProposeSendExpiryFormat.countdownLabel(remaining: remaining)
            Text(label)
                .font(.caption.weight(.medium))
                .foregroundStyle(remaining > 0 && remaining < 60 ? Color.orange : Color.secondary)
                .monospacedDigit()
                .padding(.horizontal, 10)
                .accessibilityLabel(accessibilityLabel(remaining: remaining))
        }
    }

    private func accessibilityLabel(remaining: TimeInterval) -> String {
        let total = max(0, Int(remaining.rounded(.down)))
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        let seconds = total % 60
        if hours > 0 {
            return "Expires in \(hours) hours, \(minutes) minutes, \(seconds) seconds"
        }
        if minutes > 0 {
            return "Expires in \(minutes) minutes, \(seconds) seconds"
        }
        return "Expires in \(seconds) seconds"
    }
}
