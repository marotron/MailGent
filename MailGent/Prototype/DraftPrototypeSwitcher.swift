import AppKit
import SwiftUI

enum DraftPrototypeVariant: String, CaseIterable, Identifiable {
    case copyPaste
    case draftLedger

    var id: String { rawValue }

    var key: String {
        switch self {
        case .copyPaste: "A"
        case .draftLedger: "B"
        }
    }

    var title: String {
        switch self {
        case .copyPaste: "Copy-paste"
        case .draftLedger: "Draft ledger"
        }
    }

    var label: String { "\(key) — \(title)" }
}

/// Throwaway chrome. Not part of the layouts under evaluation.
struct DraftPrototypeSwitcher: View {
    @Binding var variant: DraftPrototypeVariant

    var body: some View {
        HStack(spacing: 8) {
            Button {
                cycle(-1)
            } label: {
                Image(systemName: "chevron.left")
            }
            .help("Previous layout")
            Text(variant.label)
                .font(.caption.weight(.semibold))
                .monospacedDigit()
                .frame(minWidth: 160)
            Button {
                cycle(1)
            } label: {
                Image(systemName: "chevron.right")
            }
            .help("Next layout")
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(.black.opacity(0.82), in: Capsule())
        .foregroundStyle(.white)
        .shadow(radius: 10)
    }

    func cycle(_ step: Int) {
        let all = DraftPrototypeVariant.allCases
        guard let index = all.firstIndex(of: variant) else { return }
        variant = all[(index + step + all.count) % all.count]
    }

    static func isEditingText() -> Bool {
        let responder = NSApp.keyWindow?.firstResponder
        return responder is NSTextView || responder is NSTextField
    }
}
