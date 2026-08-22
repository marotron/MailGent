import AppKit
import MailStore
import SwiftUI
import WebKit

struct SourceChip: View {
    let session: CompanionSession
    let accountID: String
    let placement: String

    var body: some View {
        HStack(spacing: 6) {
            Text(session.accountLabel(accountID))
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(.quaternary, in: RoundedRectangle(cornerRadius: 4))
            Text(placement)
                .foregroundStyle(.secondary)
        }
        .font(.caption)
    }
}

struct PartialBadge: View {
    var body: some View {
        Text("Partial")
            .font(.caption2.weight(.semibold))
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .foregroundStyle(.orange)
            .background(.orange.opacity(0.15), in: Capsule())
    }
}

struct AddressBadge: View {
    let email: String

    var body: some View {
        Text(email)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(.quaternary, in: RoundedRectangle(cornerRadius: 4))
    }
}

/// `Name <email@x>` → display name + email; bare address → email only.
struct MailAddressParts: Equatable {
    let name: String?
    let email: String?

    static func parse(_ raw: String) -> MailAddressParts {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return MailAddressParts(name: nil, email: nil) }

        if let open = trimmed.lastIndex(of: "<"),
           let close = trimmed.lastIndex(of: ">"),
           open < close
        {
            let email = String(trimmed[trimmed.index(after: open)..<close])
                .trimmingCharacters(in: .whitespacesAndNewlines)
            var name = String(trimmed[..<open]).trimmingCharacters(in: .whitespacesAndNewlines)
            if name.count >= 2, name.hasPrefix("\""), name.hasSuffix("\"") {
                name = String(name.dropFirst().dropLast())
            }
            return MailAddressParts(
                name: name.isEmpty ? nil : name,
                email: email.isEmpty ? nil : email
            )
        }
        if trimmed.contains("@") {
            return MailAddressParts(name: nil, email: trimmed)
        }
        return MailAddressParts(name: trimmed, email: nil)
    }
}

struct AddressLine<Trailing: View>: View {
    let label: String
    let raw: String
    @ViewBuilder var trailing: () -> Trailing

    init(label: String, raw: String, @ViewBuilder trailing: @escaping () -> Trailing) {
        self.label = label
        self.raw = raw
        self.trailing = trailing
    }

    var body: some View {
        let parts = MailAddressParts.parse(raw)
        HStack(spacing: 6) {
            Text(label)
                .foregroundStyle(.secondary)
            if let name = parts.name {
                Text(name)
            }
            if let email = parts.email {
                AddressBadge(email: email)
            }
            if parts.name == nil, parts.email == nil, !raw.isEmpty {
                Text(raw)
            }
            trailing()
            Spacer(minLength: 0)
        }
        .font(.caption)
    }
}

extension AddressLine where Trailing == EmptyView {
    init(label: String, raw: String) {
        self.init(label: label, raw: raw) { EmptyView() }
    }
}

struct BodyFormatPicker: View {
    @Binding var showRaw: Bool

    var body: some View {
        Picker("Body format", selection: $showRaw) {
            Text("Pretty").tag(false)
            Text("Raw").tag(true)
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .frame(maxWidth: 160)
    }
}

struct MessageBodyView: View {
    let readBody: ReadBody
    var htmlBody: String? = nil
    var rawBody: String = ""
    var showRaw: Bool = false

    private var canShowRaw: Bool {
        showRaw && !rawBody.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var prettyHTML: String? {
        guard let htmlBody,
              !htmlBody.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else { return nil }
        return htmlBody
    }

    var body: some View {
        Group {
            if canShowRaw {
                Text(rawBody)
                    .font(.body.monospaced())
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else if let html = prettyHTML {
                HTMLMailView(html: Self.documentHTML(html))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                switch readBody {
                case .text(let text):
                    LinkAwareBodyText(attributed: Self.prettyAttributed(text))
                        .frame(maxWidth: .infinity, alignment: .leading)
                case .notAvailable:
                    Text("Body not available")
                        .foregroundStyle(.secondary)
                        .italic()
                case .notGranted:
                    Text("Body not granted")
                        .foregroundStyle(.secondary)
                        .italic()
                }
            }
        }
    }

    private static func documentHTML(_ html: String) -> String {
        let trimmed = html.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.range(of: "<html", options: .caseInsensitive) != nil {
            return trimmed
        }
        return """
        <!DOCTYPE html>
        <html>
        <head>
        <meta charset="utf-8">
        <style>
          :root { color-scheme: light dark; }
          body {
            font: -apple-system-body;
            font-family: -apple-system, BlinkMacSystemFont, sans-serif;
            margin: 0;
            padding: 0;
            background: transparent;
          }
          img { max-width: 100%; height: auto; }
        </style>
        </head>
        <body>\(trimmed)</body>
        </html>
        """
    }

    /// Email bodies break full Markdown parses; linkify `[label](url)` + bare URLs instead.
    private static func prettyAttributed(_ text: String) -> AttributedString {
        var options = AttributedString.MarkdownParsingOptions()
        options.interpretedSyntax = .inlineOnlyPreservingWhitespace
        if let attributed = try? AttributedString(markdown: text, options: options),
           attributed.runs.contains(where: { $0.link != nil })
        {
            return attributed
        }
        return linkified(text)
    }

    private static func linkified(_ text: String) -> AttributedString {
        var output = AttributedString()
        let ns = text as NSString
        let full = NSRange(location: 0, length: ns.length)
        guard let regex = try? NSRegularExpression(
            pattern: #"\[([^\]\n]+)\]\(([^)\s]+)\)|(https?://[^\s<>\]\)]+)"#
        ) else {
            return AttributedString(text)
        }

        var cursor = 0
        for match in regex.matches(in: text, range: full) {
            if match.range.location > cursor {
                output.append(AttributedString(
                    ns.substring(with: NSRange(location: cursor, length: match.range.location - cursor))
                ))
            }

            if match.range(at: 1).location != NSNotFound {
                let label = ns.substring(with: match.range(at: 1))
                let urlString = ns.substring(with: match.range(at: 2))
                output.append(linkRun(label: label, urlString: urlString))
            } else if match.range(at: 3).location != NSNotFound {
                let urlString = ns.substring(with: match.range(at: 3))
                    .trimmingCharacters(in: CharacterSet(charactersIn: ".,;:!?)"))
                output.append(linkRun(label: urlString, urlString: urlString))
            }

            cursor = match.range.location + match.range.length
        }
        if cursor < ns.length {
            output.append(AttributedString(ns.substring(from: cursor)))
        }
        return output
    }

    private static func linkRun(label: String, urlString: String) -> AttributedString {
        var run = AttributedString(label)
        if let url = URL(string: urlString) {
            run.link = url
            run.foregroundColor = .accentColor
            run.underlineStyle = .single
        }
        return run
    }
}

/// Renders HTML mail; WebKit owns scrolling. Selection/copy work; links open in the browser.
private struct HTMLMailView: NSViewRepresentable {
    let html: String

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.defaultWebpagePreferences.allowsContentJavaScript = true
        let webView = WKWebView(frame: .zero, configuration: config)
        webView.setValue(false, forKey: "drawsBackground")
        webView.navigationDelegate = context.coordinator
        webView.allowsMagnification = true
        return webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        guard context.coordinator.loadedHTML != html else { return }
        context.coordinator.loadedHTML = html
        webView.loadHTMLString(html, baseURL: nil)
    }

    final class Coordinator: NSObject, WKNavigationDelegate {
        var loadedHTML: String?

        func webView(
            _ webView: WKWebView,
            decidePolicyFor navigationAction: WKNavigationAction,
            decisionHandler: @escaping (WKNavigationActionPolicy) -> Void
        ) {
            if navigationAction.navigationType == .linkActivated,
               let url = navigationAction.request.url
            {
                NSWorkspace.shared.open(url)
                decisionHandler(.cancel)
                return
            }
            decisionHandler(.allow)
        }
    }
}

/// AppKit text view so link hover shows the pointing-hand cursor (SwiftUI `Text` does not).
private struct LinkAwareBodyText: NSViewRepresentable {
    let attributed: AttributedString

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context: Context) -> NSTextView {
        let textView = NSTextView()
        textView.drawsBackground = false
        textView.isEditable = false
        textView.isRichText = true
        textView.isSelectable = true
        textView.allowsUndo = false
        textView.textContainerInset = .zero
        textView.textContainer?.lineFragmentPadding = 0
        textView.textContainer?.widthTracksTextView = true
        textView.isHorizontallyResizable = false
        textView.isVerticallyResizable = true
        textView.autoresizingMask = [.width]
        textView.setContentHuggingPriority(.defaultLow, for: .horizontal)
        textView.setContentHuggingPriority(.required, for: .vertical)
        textView.linkTextAttributes = [
            .foregroundColor: NSColor.linkColor,
            .underlineStyle: NSUnderlineStyle.single.rawValue,
            .cursor: NSCursor.pointingHand,
        ]
        textView.delegate = context.coordinator
        return textView
    }

    func updateNSView(_ textView: NSTextView, context: Context) {
        let bridged = NSMutableAttributedString(attributedString: NSAttributedString(attributed))
        let font = NSFont.preferredFont(forTextStyle: .body)
        bridged.addAttribute(.font, value: font, range: NSRange(location: 0, length: bridged.length))
        textView.textStorage?.setAttributedString(bridged)
    }

    func sizeThatFits(_ proposal: ProposedViewSize, nsView: NSTextView, context: Context) -> CGSize? {
        let width = proposal.width ?? nsView.bounds.width
        guard width > 0, let container = nsView.textContainer, let layout = nsView.layoutManager else {
            return nil
        }
        container.containerSize = CGSize(width: width, height: .greatestFiniteMagnitude)
        nsView.frame.size.width = width
        layout.ensureLayout(for: container)
        let used = layout.usedRect(for: container)
        return CGSize(width: width, height: ceil(used.height))
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        func textView(_ textView: NSTextView, clickedOnLink link: Any, at charIndex: Int) -> Bool {
            if let url = link as? URL {
                NSWorkspace.shared.open(url)
                return true
            }
            if let string = link as? String, let url = URL(string: string) {
                NSWorkspace.shared.open(url)
                return true
            }
            return false
        }
    }
}

struct OpenInMailButton: View {
    var session: CompanionSession

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Button("Open in Apple Mail") {
                session.openInMail()
            }
            if let handoffNote = session.handoffNote {
                Text(handoffNote)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

struct PlacementMenu: View {
    @Bindable var session: CompanionSession

    var body: some View {
        Menu(session.selectedPlacement.map {
            "\(session.accountLabel($0.accountID)) · \($0.id)"
        } ?? "All placements") {
            Button("All placements") {
                session.selectedPlacement = nil
                session.refresh()
            }
            ForEach(session.placements, id: \.rowID) { placement in
                Button("\(session.accountLabel(placement.accountID)) · \(placement.id)") {
                    session.selectedPlacement = placement
                    session.refresh()
                }
            }
        }
    }
}

/// Shared menu / control-center snapshot strings for ingest, source, and agent.
@MainActor
struct CompanionStatusCopy {
    let session: CompanionSession
    let now: Date

    var lastIngest: String {
        guard let date = session.lastIngestAt else { return "—" }
        let clock = date.formatted(date: .omitted, time: .shortened)
        return "\(clock) (\(Self.relativeAge(from: date, to: now)))"
    }

    var newMessages: String {
        guard let since = session.lastNewSinceAt else {
            return "\(session.lastNewCount)"
        }
        let clock = since.formatted(date: .omitted, time: .shortened)
        return "\(session.lastNewCount) (since \(clock))"
    }

    var source: String { session.source.title }

    var connectedAgent: String { session.agents.agent?.name ?? "—" }

    var lastAgentRequest: String {
        guard let entry = session.agents.lastAgentRequest else { return "—" }
        return "\(entry.kind.rawValue) · \(Self.relativeAge(from: entry.at, to: now))"
    }

    static func relativeAge(from date: Date, to now: Date) -> String {
        let seconds = max(0, Int(now.timeIntervalSince(date)))
        if seconds < 60 { return "\(seconds)s ago" }
        let minutes = seconds / 60
        if minutes < 60 { return "\(minutes)m ago" }
        let hours = minutes / 60
        if hours < 48 { return "\(hours)h ago" }
        return "\(hours / 24)d ago"
    }
}

/// Label/value snapshot used by Control Center. Menu keeps its own action buttons.
struct CompanionStatusMetrics: View {
    let session: CompanionSession

    var body: some View {
        TimelineView(.periodic(from: .now, by: 15)) { context in
            let copy = CompanionStatusCopy(session: session, now: context.date)
            VStack(alignment: .leading, spacing: 2) {
                row("Last ingest", copy.lastIngest)
                row("New", copy.newMessages)
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text("Source")
                        .foregroundStyle(.secondary)
                        .frame(width: 118, alignment: .leading)
                    Text(copy.source)
                        .foregroundStyle(session.source == .fixture ? Color.purple : Color.primary)
                        .fontWeight(session.source == .fixture ? .semibold : .regular)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                row("Connected agent", copy.connectedAgent)
                row("Last agent request", copy.lastAgentRequest)
            }
            .font(.callout)
        }
    }

    private func row(_ title: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(title)
                .foregroundStyle(.secondary)
                .frame(width: 118, alignment: .leading)
            Text(value)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

// MARK: - Access log + grant desk chrome

extension AuditKind {
    var badgeTitle: String {
        switch self {
        case .pair: "pair"
        case .search: "search"
        case .list: "list"
        case .listPlacements: "placements"
        case .get: "get"
        case .createDraft: "create"
        case .updateDraft: "update"
        case .updateIndex: "ingest"
        case .status: "status"
        case .setSource: "source"
        case .revoke: "revoke"
        }
    }

    var systemImage: String {
        switch self {
        case .pair: "link"
        case .search: "magnifyingglass"
        case .list: "list.bullet"
        case .listPlacements: "folder"
        case .get: "envelope.open"
        case .createDraft: "square.and.pencil"
        case .updateDraft: "pencil"
        case .updateIndex: "arrow.triangle.2.circlepath"
        case .status: "chart.bar"
        case .setSource: "switch.2"
        case .revoke: "xmark.circle"
        }
    }
}

struct AuditKindBadge: View {
    let kind: AuditKind

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: kind.systemImage)
                .font(.caption2.weight(.semibold))
            Text(kind.badgeTitle)
                .font(.caption.weight(.semibold).monospaced())
        }
        .foregroundStyle(Color.accentColor)
        .padding(.horizontal, 7)
        .padding(.vertical, 3)
        .background(Color.accentColor.opacity(0.12), in: Capsule())
        .overlay {
            Capsule().strokeBorder(Color.accentColor.opacity(0.35), lineWidth: 0.5)
        }
        .accessibilityLabel(kind.badgeTitle)
    }
}

struct AuditOutcomeIcon: View {
    let outcome: AuditOutcome

    var body: some View {
        switch outcome {
        case .ok:
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.green)
                .help("Succeeded")
                .accessibilityLabel("Succeeded")
        case .error(let message):
            Image(systemName: "xmark.circle.fill")
                .foregroundStyle(.orange)
                .help(message.isEmpty ? "Failed" : message)
                .accessibilityLabel("Failed")
        }
    }
}

struct AgentGlyph: View {
    let name: String
    var size: CGFloat = 16

    private var isCursor: Bool {
        name.compare("Cursor", options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame
    }

    var body: some View {
        Group {
            if isCursor {
                CursorMark()
            } else {
                Image(systemName: "cpu")
                    .font(.system(size: size * 0.62, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: size, height: size)
                    .background(
                        .quaternary,
                        in: RoundedRectangle(cornerRadius: 4, style: .continuous)
                    )
            }
        }
        .frame(width: size, height: size)
        .help(name)
        .accessibilityLabel(name)
    }
}

struct CursorMark: View {
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 4, style: .continuous)
                .fill(.primary)
            CursorPointerShape()
                .fill(Color(nsColor: .windowBackgroundColor))
                .padding(2.5)
        }
        .accessibilityLabel("Cursor")
    }
}

private struct CursorPointerShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let w = rect.width
        let h = rect.height
        path.move(to: CGPoint(x: w * 0.16, y: h * 0.08))
        path.addLine(to: CGPoint(x: w * 0.16, y: h * 0.84))
        path.addLine(to: CGPoint(x: w * 0.38, y: h * 0.64))
        path.addLine(to: CGPoint(x: w * 0.54, y: h * 0.96))
        path.addLine(to: CGPoint(x: w * 0.68, y: h * 0.90))
        path.addLine(to: CGPoint(x: w * 0.50, y: h * 0.56))
        path.addLine(to: CGPoint(x: w * 0.82, y: h * 0.56))
        path.closeSubpath()
        return path
    }
}

struct RawPrettyHeader: View {
    let title: String
    @Binding var showRaw: Bool

    var body: some View {
        HStack(alignment: .center, spacing: 8) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            Text(showRaw ? "Raw" : "Pretty")
                .font(.caption2.weight(.semibold))
                .padding(.horizontal, 6)
                .padding(.vertical, 1)
                .foregroundStyle(.secondary)
                .background(.quaternary, in: Capsule())
                .accessibilityLabel(showRaw ? "Raw view" : "Pretty view")
            Spacer(minLength: 8)
            BodyFormatPicker(showRaw: $showRaw)
        }
    }
}

struct GrantFieldChip: View {
    let title: String
    let isOn: Bool
    var systemImage: String? = nil
    var strikethroughWhenOff: Bool = false

    var body: some View {
        HStack(spacing: 4) {
            if let systemImage {
                Image(systemName: systemImage)
                    .font(.caption2)
            }
            Text(title)
                .font(.caption)
        }
        .foregroundStyle(isOn ? Color.accentColor : Color.secondary)
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(
            Capsule()
                .fill(isOn ? Color.accentColor.opacity(0.12) : Color.secondary.opacity(0.08))
        )
        .overlay(
            Capsule()
                .strokeBorder(
                    isOn ? Color.accentColor.opacity(0.45) : Color.secondary.opacity(0.25),
                    lineWidth: isOn ? 1.5 : 0.5
                )
        )
        .strikethrough(strikethroughWhenOff && !isOn, color: Color.secondary.opacity(0.45))
    }
}

struct GrantFieldBadgeRow: View {
    let fields: GrantFields
    var interactive: Bool = false
    var onToggle: ((WritableKeyPath<GrantFields, Bool>) -> Void)? = nil

    private static let items: [(String, WritableKeyPath<GrantFields, Bool>)] = [
        ("subj", \.subject),
        ("from", \.from),
        ("to", \.to),
        ("date", \.date),
        ("body", \.body),
        ("att", \.attachmentMetadata),
        ("bytes", \.attachmentContent),
    ]

    var body: some View {
        HStack(spacing: 2) {
            ForEach(Self.items, id: \.0) { label, keyPath in
                let on = fields[keyPath: keyPath]
                if interactive, let onToggle {
                    Button {
                        onToggle(keyPath)
                    } label: {
                        compactBadge(label, on: on)
                    }
                    .buttonStyle(.plain)
                    .help("Toggle \(label)")
                } else {
                    compactBadge(label, on: on)
                }
            }
        }
    }

    private func compactBadge(_ label: String, on: Bool) -> some View {
        Text(label)
            .font(.system(size: 8, weight: on ? .medium : .regular))
            .foregroundStyle(on ? Color.accentColor : Color.secondary.opacity(0.55))
            .padding(.horizontal, 4)
            .frame(height: 12)
            .background(
                Capsule()
                    .fill(on ? Color.accentColor.opacity(0.12) : Color.secondary.opacity(0.08))
            )
            .overlay(
                Capsule()
                    .strokeBorder(
                        on ? Color.accentColor.opacity(0.35) : Color.secondary.opacity(0.2),
                        lineWidth: 0.5
                    )
            )
            .strikethrough(!on, color: Color.secondary.opacity(0.45))
    }
}

struct GrantFieldCoverage: View {
    let fields: GrantFields

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Envelope")
                .font(.caption.weight(.semibold))
            HStack(spacing: 6) {
                GrantFieldChip(title: "Subject", isOn: fields.subject, systemImage: "text.alignleft", strikethroughWhenOff: true)
                GrantFieldChip(title: "From", isOn: fields.from, systemImage: "envelope", strikethroughWhenOff: true)
                GrantFieldChip(title: "To", isOn: fields.to, systemImage: "envelope", strikethroughWhenOff: true)
                GrantFieldChip(title: "Date & Time", isOn: fields.date, systemImage: "calendar", strikethroughWhenOff: true)
            }
            Text("Content")
                .font(.caption.weight(.semibold))
            HStack(spacing: 6) {
                GrantFieldChip(
                    title: "Body / snippet",
                    isOn: fields.body,
                    systemImage: "text.alignleft",
                    strikethroughWhenOff: true
                )
                GrantFieldChip(
                    title: "Attachment names",
                    isOn: fields.attachmentMetadata,
                    systemImage: "paperclip",
                    strikethroughWhenOff: true
                )
                GrantFieldChip(
                    title: "Attachment content",
                    isOn: fields.attachmentContent,
                    systemImage: "paperclip",
                    strikethroughWhenOff: true
                )
            }
        }
    }
}

struct HatchDeniedLabel: View {
    var placeholder: String = " "
    var fixedHeight: CGFloat? = nil

    var body: some View {
        Group {
            if let fixedHeight {
                Color.clear
                    .frame(maxWidth: .infinity, minHeight: fixedHeight, maxHeight: fixedHeight)
            } else {
                Text(placeholder)
                    .font(.caption)
                    .foregroundStyle(.clear)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 2)
            }
        }
        .padding(.horizontal, 4)
        .background {
            HatchPattern()
                .opacity(0.9)
        }
        .overlay {
            Text("not granted")
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(.secondary)
                .tracking(0.4)
        }
        .clipShape(RoundedRectangle(cornerRadius: 4))
    }
}

struct HatchPattern: View {
    var body: some View {
        Canvas { context, size in
            let spacing: CGFloat = 5
            var path = Path()
            let extent = size.width + size.height
            var x: CGFloat = -size.height
            while x < extent {
                path.move(to: CGPoint(x: x, y: 0))
                path.addLine(to: CGPoint(x: x + size.height, y: size.height))
                x += spacing
            }
            context.stroke(
                path,
                with: .color(Color.secondary.opacity(0.45)),
                lineWidth: 1
            )
            context.fill(
                Path(CGRect(origin: .zero, size: size)),
                with: .color(Color.secondary.opacity(0.08))
            )
        }
    }
}
