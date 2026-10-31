import Foundation
import SwiftUI

/// In-dialog handoff phases for `propose_send` (Variant A: stay open until Done).
@MainActor
final class SendProposalConfirmModel: ObservableObject {
    enum Phase: Equatable {
        case review
        case sending
        case handedOff
        case failed(String)
    }

    @Published var phase: Phase = .review

    var isReview: Bool {
        if case .review = phase { return true }
        return false
    }

    var windowTitle: String {
        switch phase {
        case .review: "Send proposed mail?"
        case .sending: "Sending…"
        case .handedOff: "Handed to Mail"
        case .failed: "Send failed"
        }
    }
}
