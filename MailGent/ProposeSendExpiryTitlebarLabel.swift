import MailStore
import SwiftUI

/// Titlebar-trailing hard-timeout countdown for human wait (Ask + propose_send).
struct ProposeSendExpiryTitlebarLabel: View {
    let expiresAt: Date

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let remaining = expiresAt.timeIntervalSince(context.date)
            let expired = remaining <= 0
            let label = expired
                ? "Expired at \(expiresAt.formatted(date: .omitted, time: .shortened))"
                : ProposeSendExpiryFormat.countdownLabel(remaining: remaining)
            Text(label)
                .font(.caption.weight(.medium))
                .foregroundStyle(expired ? Color.red : (remaining < 60 ? Color.orange : Color.secondary))
                .monospacedDigit()
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
                .padding(.horizontal, 10)
                .accessibilityLabel(expired ? label : accessibilityLabel(remaining: remaining))
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
