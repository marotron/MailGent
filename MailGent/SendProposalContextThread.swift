import MailStore
import SwiftUI

/// E-thin × F-full × P4 context rail for experimental propose-send.
struct SendProposalContextThreadView: View {
    let resolved: ProposeSendResolvedContext
    @Binding var thin: Bool
    @Binding var selectedID: String?
    /// When true, history (non-draft) rows are dimmed.
    @Binding var spotlightDraft: Bool
    var onOpenOriginal: (ContextThreadOriginal) -> Void = { _ in }

    /// Bubble corner radius; ownership-side top corner stays sharp (0).
    private static let cardRadius: CGFloat = 14
    /// Space between white cards. Applied as half-padding on each row *before*
    /// the band/pane background so grey stays continuous while cards separate.
    private static let eventGap: CGFloat = 8

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            ScrollViewReader { proxy in
                ScrollView {
                    // spacing 0 + no horizontal pad: grey pane / private bands go edge-to-edge;
                    // card inset + inter-card gap live on the row (padding then background).
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(resolved.items) { item in
                            row(item)
                                .id(item.id)
                                .opacity(dimOpacity(for: item))
                                .saturation(dimSaturation(for: item))
                        }
                    }
                }
                .onChange(of: selectedID) { _, id in
                    guard let id else { return }
                    withAnimation(.easeInOut(duration: 0.2)) {
                        proxy.scrollTo(id, anchor: .center)
                    }
                }
            }
        }
        .background(Color(nsColor: .controlBackgroundColor))
        .overlay(
            Rectangle()
                .strokeBorder(Color.primary.opacity(0.08), lineWidth: 1)
        )
    }

    private var header: some View {
        HStack(spacing: 6) {
            Button {
                thin.toggle()
            } label: {
                Image(systemName: thin ? "chevron.right" : "chevron.left")
                    .font(.caption.weight(.semibold))
            }
            .buttonStyle(.borderless)
            .help(thin ? "Expand context" : "Collapse context")

            Text("Case")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
            Text(resolved.caseLabel)
                .font(.caption2)
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer(minLength: 4)
            Text("\(max(0, resolved.items.count - 1))")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .help("Context events (excluding draft)")
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 7)
        .background(Color.primary.opacity(0.04))
    }

    @ViewBuilder
    private func row(_ item: ContextThreadItem) -> some View {
        let selected = selectedID == item.id
        if thin {
            Button {
                select(item)
            } label: {
                thinRow(item, selected: selected)
            }
            .buttonStyle(.plain)
        } else {
            fullRow(item, selected: selected)
                .contentShape(Rectangle())
                .onTapGesture { select(item) }
        }
    }

    private func select(_ item: ContextThreadItem) {
        selectedID = item.id
        spotlightDraft = item.isDraft
    }

    private func thinRow(_ item: ContextThreadItem, selected: Bool) -> some View {
        let privateBand = item.scope == .private && !item.isDraft
        return HStack(alignment: .top, spacing: 3) {
            avatarColumn(side: .left, item: item)
                .frame(width: 16)
            thinCard(item, selected: selected)
                .frame(maxWidth: .infinity, alignment: stretchAlignment(item))
            avatarColumn(side: .right, item: item)
                .frame(width: 16)
        }
        .padding(.vertical, Self.eventGap / 2)
        .padding(.horizontal, 4)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(rowBackground(privateBand: privateBand))
    }

    private func fullRow(_ item: ContextThreadItem, selected: Bool) -> some View {
        let privateBand = item.scope == .private && !item.isDraft
        return HStack(alignment: .top, spacing: 6) {
            avatarColumn(side: .left, item: item)
                .frame(width: 28)
            fullCard(item, selected: selected)
                .frame(maxWidth: .infinity, alignment: .leading)
            avatarColumn(side: .right, item: item)
                .frame(width: 28)
        }
        .padding(.vertical, Self.eventGap / 2)
        .padding(.horizontal, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(rowBackground(privateBand: privateBand))
    }

    /// Fills inter-card padding so grey never gaps; private is a touch darker.
    private func rowBackground(privateBand: Bool) -> Color {
        privateBand
            ? Color.primary.opacity(0.08)
            : Color(nsColor: .controlBackgroundColor)
    }

    private enum AvatarSide { case left, right }

    @ViewBuilder
    private func avatarColumn(side: AvatarSide, item: ContextThreadItem) -> some View {
        let show: Bool = {
            if item.scope == .private && !item.isDraft { return false }
            switch item.ownership {
            case .them: return side == .left
            case .you: return side == .right
            case .both: return true
            }
        }()
        if show {
            Text(initials(for: item, side: side))
                .font(.system(size: thin ? 7 : 9, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: thin ? 14 : 22, height: thin ? 14 : 22)
                .background(Circle().fill(avatarColor(for: item, side: side)))
                .offset(x: thin ? avatarPeek(side: side, item: item) : 0)
        } else {
            Color.clear.frame(width: thin ? 14 : 22, height: thin ? 14 : 22)
        }
    }

    private func avatarPeek(side: AvatarSide, item: ContextThreadItem) -> CGFloat {
        // Thin mode: keep a small gap — nudge avatars outward from the card.
        switch (side, item.ownership) {
        case (.left, .them), (.left, .both): return -1
        case (.right, .you), (.right, .both): return 1
        default: return 0
        }
    }

    private func stretchAlignment(_ item: ContextThreadItem) -> Alignment {
        switch item.ownership {
        case .them: return .leading
        case .you, .both: return .trailing
        }
    }

    private func thinCard(_ item: ContextThreadItem, selected: Bool) -> some View {
        let sharp = sharpCorner(for: item)
        return VStack(alignment: .leading, spacing: 4) {
            kindBadge(item.kind)
            Text(shortDate(item.at))
                .font(.system(size: 9))
                .foregroundStyle(.secondary)
        }
        .padding(6)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(item.isDraft ? Color.yellow.opacity(0.22) : Color(nsColor: .textBackgroundColor))
        .clipShape(SharpCornerShape(sharp: sharp, radius: Self.cardRadius))
        .overlay(cardStroke(selected: selected, sharp: sharp))
    }

    private func fullCard(_ item: ContextThreadItem, selected: Bool) -> some View {
        let sharp = sharpCorner(for: item)
        let expanded = selected && !item.isDraft
        return VStack(alignment: .leading, spacing: 6) {
            // Meta
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                kindBadge(item.kind)
                if let party = item.party?.name, !party.isEmpty {
                    Text(party)
                        .font(.caption2.weight(.semibold))
                        .lineLimit(1)
                }
                Spacer(minLength: 4)
                Text(shortDate(item.at))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            if let from = item.from, !from.isEmpty {
                metaLine(label: "From", value: from)
            }
            if let subject = item.subject, !subject.isEmpty {
                metaLine(label: "Subject", value: subject)
            }

            Text(item.summary)
                .font(.caption2.weight(.medium))
                .lineLimit(expanded ? 4 : 2)
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)

            if let reason = item.unavailableReason {
                Text(reason)
                    .font(.caption2)
                    .foregroundStyle(.orange)
            }

            sourceAndLinkChips(item)

            // Body below divider when focused (draft body lives in the right pane).
            if expanded {
                if let detail = item.detail, !detail.isEmpty {
                    Divider().opacity(0.35)
                    ScrollView {
                        Text(ContextThreadDetailText.attributed(detail: detail, original: item.original))
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .textSelection(.enabled)
                    }
                    .frame(maxHeight: 220)
                } else if item.unavailableReason == nil, item.original != nil {
                    Divider().opacity(0.35)
                    Text("Body not available here — open the original.")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(item.isDraft ? Color.yellow.opacity(0.22) : Color(nsColor: .textBackgroundColor))
        .clipShape(SharpCornerShape(sharp: sharp, radius: Self.cardRadius))
        .overlay(cardStroke(selected: selected, sharp: sharp))
    }

    private func metaLine(label: String, value: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 4) {
            Text(label)
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(.secondary)
            Text(value)
                .font(.system(size: 9))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
                .textSelection(.enabled)
        }
    }

    @ViewBuilder
    private func sourceAndLinkChips(_ item: ContextThreadItem) -> some View {
        let hasOriginal = item.original != nil && !item.isDraft
        let hasLinks = !item.linkChips.isEmpty
        if hasOriginal || hasLinks {
            HStack(spacing: 4) {
                if let original = item.original, !item.isDraft {
                    Button {
                        onOpenOriginal(original)
                    } label: {
                        Label(originalChipLabel(original), systemImage: originalChipSymbol(original))
                            .labelStyle(.titleAndIcon)
                            .font(.system(size: 9, weight: .medium))
                            .padding(.horizontal, 5)
                            .padding(.vertical, 2)
                            .background(Capsule().fill(originalChipFill(original)))
                    }
                    .buttonStyle(.plain)
                    .help(originalChipHelp(original))
                }
                ForEach(Array(item.linkChips.enumerated()), id: \.offset) { _, chip in
                    Button {
                        selectedID = chip.peerID
                        spotlightDraft = chip.peerID == "draft"
                    } label: {
                        Text(chip.label)
                            .font(.system(size: 9, weight: .medium))
                            .padding(.horizontal, 5)
                            .padding(.vertical, 2)
                            .background(
                                Capsule()
                                    .strokeBorder(Color.primary.opacity(0.18), style: StrokeStyle(lineWidth: 1, dash: [3, 2]))
                            )
                    }
                    .buttonStyle(.plain)
                    .help("Jump to related event")
                }
            }
        }
    }

    private func originalChipLabel(_ original: ContextThreadOriginal) -> String {
        switch original {
        case .mail: return "Open in Mail"
        case let .vault(path):
            return (path as NSString).lastPathComponent
        }
    }

    private func originalChipSymbol(_ original: ContextThreadOriginal) -> String {
        switch original {
        case .mail: return "envelope"
        case .vault: return "doc.text"
        }
    }

    private func originalChipFill(_ original: ContextThreadOriginal) -> Color {
        switch original {
        case .mail: return Color.blue.opacity(0.14)
        case .vault: return Color.purple.opacity(0.14)
        }
    }

    private func originalChipHelp(_ original: ContextThreadOriginal) -> String {
        switch original {
        case .mail: return "Open this message in Apple Mail"
        case let .vault(path): return "Open \(path)"
        }
    }

    private func sharpCorner(for item: ContextThreadItem) -> SharpCorner {
        switch item.ownership {
        case .them: return .topLeading
        case .you: return .topTrailing
        case .both: return .none
        }
    }

    private func cardStroke(selected: Bool, sharp: SharpCorner) -> some View {
        SharpCornerShape(sharp: sharp, radius: Self.cardRadius)
            .strokeBorder(
                selected
                    ? Color.primary.opacity(0.55)
                    : Color.primary.opacity(0.1),
                lineWidth: selected ? 1.5 : 1
            )
    }

    private func kindBadge(_ kind: SendProposalEventKind) -> some View {
        Image(systemName: kindSymbol(kind))
            .font(.system(size: 9, weight: .semibold))
            .foregroundStyle(.secondary)
            .help(kind.rawValue)
    }

    private func kindSymbol(_ kind: SendProposalEventKind) -> String {
        switch kind {
        case .mail: return "envelope.fill"
        case .phone: return "phone.fill"
        case .video: return "video.fill"
        case .note: return "note.text"
        case .log: return "list.bullet.rectangle"
        }
    }

    private func initials(for item: ContextThreadItem, side: AvatarSide) -> String {
        if item.isDraft { return "You" }
        if side == .right, item.ownership == .you || item.ownership == .both {
            return "You"
        }
        if let initials = item.party?.initials, !initials.isEmpty {
            return String(initials.prefix(2))
        }
        if let name = item.party?.name {
            let parts = name.split(separator: " ")
            let letters = parts.prefix(2).compactMap(\.first).map(String.init).joined()
            return letters.isEmpty ? "?" : letters
        }
        return "?"
    }

    private func avatarColor(for item: ContextThreadItem, side: AvatarSide) -> Color {
        if item.isDraft || side == .right && (item.ownership == .you || item.ownership == .both) {
            return Color.orange.opacity(0.85)
        }
        return Color.blue.opacity(0.85)
    }

    private func shortDate(_ date: Date) -> String {
        if date == .distantFuture { return "Draft" }
        let f = DateFormatter()
        f.dateStyle = .short
        f.timeStyle = .short
        return f.string(from: date)
    }

    private func dimOpacity(for item: ContextThreadItem) -> Double {
        guard spotlightDraft, !item.isDraft else { return 1 }
        return 0.72
    }

    private func dimSaturation(for item: ContextThreadItem) -> Double {
        guard spotlightDraft, !item.isDraft else { return 1 }
        return 0.85
    }
}

private enum SharpCorner {
    case none
    case topLeading
    case topTrailing
}

/// Variant F sharp top corner on the ownership side.
private struct SharpCornerShape: Shape, InsettableShape {
    var sharp: SharpCorner
    var radius: CGFloat
    var insetAmount: CGFloat = 0

    func path(in rect: CGRect) -> Path {
        let r = max(0, radius - insetAmount)
        let rect = rect.insetBy(dx: insetAmount, dy: insetAmount)
        var path = Path()
        let tl: CGFloat = sharp == .topLeading ? 0 : r
        let tr: CGFloat = sharp == .topTrailing ? 0 : r
        let br: CGFloat = r
        let bl: CGFloat = r
        path.move(to: CGPoint(x: rect.minX + tl, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX - tr, y: rect.minY))
        if tr > 0 {
            path.addArc(
                center: CGPoint(x: rect.maxX - tr, y: rect.minY + tr),
                radius: tr,
                startAngle: .degrees(-90),
                endAngle: .degrees(0),
                clockwise: false
            )
        } else {
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        }
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - br))
        path.addArc(
            center: CGPoint(x: rect.maxX - br, y: rect.maxY - br),
            radius: br,
            startAngle: .degrees(0),
            endAngle: .degrees(90),
            clockwise: false
        )
        path.addLine(to: CGPoint(x: rect.minX + bl, y: rect.maxY))
        path.addArc(
            center: CGPoint(x: rect.minX + bl, y: rect.maxY - bl),
            radius: bl,
            startAngle: .degrees(90),
            endAngle: .degrees(180),
            clockwise: false
        )
        path.addLine(to: CGPoint(x: rect.minX, y: rect.minY + tl))
        if tl > 0 {
            path.addArc(
                center: CGPoint(x: rect.minX + tl, y: rect.minY + tl),
                radius: tl,
                startAngle: .degrees(180),
                endAngle: .degrees(270),
                clockwise: false
            )
        } else {
            path.addLine(to: CGPoint(x: rect.minX, y: rect.minY))
        }
        path.closeSubpath()
        return path
    }

    func inset(by amount: CGFloat) -> SharpCornerShape {
        var copy = self
        copy.insetAmount += amount
        return copy
    }
}
