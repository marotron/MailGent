import SwiftUI

/// Open in Apple Mail glyph — system external-link (arrow up-right from square).
struct OpenInMailGlyph: View {
    var body: some View {
        Image(systemName: "arrow.up.right.square")
            .font(.system(size: 11, weight: .medium))
            .symbolRenderingMode(.hierarchical)
            .accessibilityHidden(true)
    }
}

#Preview("Open in Mail glyph") {
    HStack(spacing: 16) {
        SecondaryActionSystemGlyph(systemImage: "eye")
        OpenInMailGlyph()
    }
    .padding(24)
    .background(Color(nsColor: .windowBackgroundColor))
}
