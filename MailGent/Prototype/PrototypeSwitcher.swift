import AppKit
import SwiftUI

enum PrototypeVariant: String, CaseIterable, Identifiable {
    case controlFirst
    case searchFirst
    case reviewDesk

    var id: String { rawValue }

    var key: String {
        switch self {
        case .controlFirst: "A"
        case .searchFirst: "B"
        case .reviewDesk: "C"
        }
    }

    var title: String {
        switch self {
        case .controlFirst: "Control-first"
        case .searchFirst: "Search-first"
        case .reviewDesk: "Review desk"
        }
    }

    var label: String { "\(key) — \(title)" }
}

/// Throwaway chrome. Not part of the layouts under evaluation.
struct PrototypeSwitcher: View {
    @Binding var variant: PrototypeVariant

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
                .frame(minWidth: 168)
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
        let all = PrototypeVariant.allCases
        guard let index = all.firstIndex(of: variant) else { return }
        variant = all[(index + step + all.count) % all.count]
    }

    static func isEditingText() -> Bool {
        let responder = NSApp.keyWindow?.firstResponder
        return responder is NSTextView || responder is NSTextField
    }
}
