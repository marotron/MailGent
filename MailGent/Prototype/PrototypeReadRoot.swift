import SwiftUI

/// Three variants of companion read IA, switchable via PrototypeSwitcher, in the menu-bar Window (not WindowGroup).
struct PrototypeReadRoot: View {
    @Bindable var session: PrototypeReadSession
    @State private var variant: PrototypeVariant = .controlFirst

    var body: some View {
        ZStack(alignment: .bottom) {
            Group {
                switch variant {
                case .controlFirst:
                    VariantControlFirst(session: session)
                case .searchFirst:
                    VariantSearchFirst(session: session)
                case .reviewDesk:
                    VariantReviewDesk(session: session)
                }
            }
            PrototypeSwitcher(variant: $variant)
                .padding(.bottom, 16)
        }
        .frame(minWidth: 720, minHeight: 480)
        .focusable()
        .onKeyPress(.leftArrow) {
            guard !PrototypeSwitcher.isEditingText() else { return .ignored }
            cycle(-1)
            return .handled
        }
        .onKeyPress(.rightArrow) {
            guard !PrototypeSwitcher.isEditingText() else { return .ignored }
            cycle(1)
            return .handled
        }
    }

    private func cycle(_ step: Int) {
        let all = PrototypeVariant.allCases
        guard let index = all.firstIndex(of: variant) else { return }
        variant = all[(index + step + all.count) % all.count]
    }
}
