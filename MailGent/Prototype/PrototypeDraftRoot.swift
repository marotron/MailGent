import SwiftUI

/// Two outbound variants. Question: does clipboard paste into Mail.app preserve value, or does a versioned ledger earn complexity?
struct PrototypeDraftRoot: View {
    @Bindable var session: PrototypeDraftSession
    @State private var variant: DraftPrototypeVariant = .copyPaste

    var body: some View {
        ZStack(alignment: .bottom) {
            Group {
                switch variant {
                case .copyPaste:
                    VariantCopyPaste(session: session)
                case .draftLedger:
                    VariantDraftLedger(session: session)
                }
            }
            DraftPrototypeSwitcher(variant: $variant)
                .padding(.bottom, 16)
        }
        .frame(minWidth: 780, minHeight: 520)
        .focusable()
        .onKeyPress(.leftArrow) {
            guard !DraftPrototypeSwitcher.isEditingText() else { return .ignored }
            cycle(-1)
            return .handled
        }
        .onKeyPress(.rightArrow) {
            guard !DraftPrototypeSwitcher.isEditingText() else { return .ignored }
            cycle(1)
            return .handled
        }
        .onChange(of: variant) { _, newValue in
            session.note("switched to \(newValue.label)")
        }
    }

    private func cycle(_ step: Int) {
        let all = DraftPrototypeVariant.allCases
        guard let index = all.firstIndex(of: variant) else { return }
        variant = all[(index + step + all.count) % all.count]
    }
}
