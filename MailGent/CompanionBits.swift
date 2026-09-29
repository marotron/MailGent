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

    static func parseList(_ raw: String) -> [MailAddressParts] {
        splitAddressList(raw).compactMap { token in
            let parts = parse(token)
            if parts.name == nil, parts.email == nil { return nil }
            return parts
        }
    }

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

    /// RFC 5322 address-list: split on commas outside quotes, comments, and angle-addr.
    static func splitAddressList(_ raw: String) -> [String] {
        var result: [String] = []
        var current = ""
        var inQuotes = false
        var inAngle = false
        var commentDepth = 0
        var escape = false

        for ch in raw {
            if escape {
                current.append(ch)
                escape = false
                continue
            }
            if ch == "\\", inQuotes || commentDepth > 0 {
                current.append(ch)
                escape = true
                continue
            }
            if commentDepth > 0 {
                if ch == "(" { commentDepth += 1 }
                else if ch == ")" { commentDepth -= 1 }
                current.append(ch)
                continue
            }
            if inQuotes {
                if ch == "\"" { inQuotes = false }
                current.append(ch)
                continue
            }
            switch ch {
            case "\"":
                inQuotes = true
                current.append(ch)
            case "<":
                inAngle = true
                current.append(ch)
            case ">":
                inAngle = false
                current.append(ch)
            case "(":
                commentDepth = 1
                current.append(ch)
            case "," where !inAngle:
                let token = current.trimmingCharacters(in: .whitespacesAndNewlines)
                if !token.isEmpty { result.append(token) }
                current = ""
            default:
                current.append(ch)
            }
        }
        let token = current.trimmingCharacters(in: .whitespacesAndNewlines)
        if !token.isEmpty { result.append(token) }
        return result
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
        let addresses = MailAddressParts.parseList(raw)
        HStack(spacing: 6) {
            Text("\(label):")
                .fontWeight(.light)
                .foregroundStyle(.secondary)
            if addresses.isEmpty {
                if !raw.isEmpty {
                    Text(raw)
                }
            } else {
                ForEach(Array(addresses.enumerated()), id: \.offset) { _, parts in
                    HStack(spacing: 6) {
                        if let name = parts.name {
                            Text(name)
                        }
                        if let email = parts.email {
                            AddressBadge(email: email)
                        }
                    }
                }
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
        .controlSize(.small)
        .fixedSize()
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
        let plain: String
        if case .text(let text) = readBody {
            plain = text
        } else {
            return htmlBody
        }
        if MailMIME.htmlLooksLikePrefix(html: htmlBody, plain: plain) {
            return nil
        }
        return htmlBody
    }

    var body: some View {
        Group {
            if canShowRaw {
                // SwiftUI `Text` blanks out past ~32k characters and on embedded NULs.
                RawBodyView(text: rawBody)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
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

/// MIME / raw body. NSTextView owns scrolling so large (or NUL-containing) payloads still draw.
private struct RawBodyView: NSViewRepresentable {
    let text: String

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSTextView.scrollableTextView()
        scrollView.drawsBackground = false
        scrollView.borderType = .noBorder
        scrollView.hasHorizontalScroller = false
        guard let textView = scrollView.documentView as? NSTextView else { return scrollView }
        textView.drawsBackground = false
        textView.isEditable = false
        textView.isSelectable = true
        textView.isRichText = false
        textView.isHorizontallyResizable = false
        textView.isVerticallyResizable = true
        textView.autoresizingMask = [.width]
        textView.font = NSFont.monospacedSystemFont(
            ofSize: NSFont.preferredFont(forTextStyle: .body).pointSize,
            weight: .regular
        )
        textView.textContainerInset = .zero
        textView.textContainer?.lineFragmentPadding = 0
        textView.textContainer?.widthTracksTextView = true
        let display = Self.displayString(from: text)
        textView.string = display
        context.coordinator.loaded = text
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = scrollView.documentView as? NSTextView else { return }
        guard context.coordinator.loaded != text else { return }
        context.coordinator.loaded = text
        textView.string = Self.displayString(from: text)
    }

    /// NSString / SwiftUI Text treat U+0000 as terminator; binary MIME parts often contain them.
    static func displayString(from text: String) -> String {
        text.replacingOccurrences(of: "\0", with: "\u{FFFD}")
    }

    final class Coordinator {
        var loaded: String?
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
enum IngestPassCopy {
    static func signed(_ value: Int) -> String {
        if value > 0 { return "+\(value)" }
        if value < 0 { return "−\(-value)" }
        return "0"
    }

    static func summary(newCount: Int, removedCount: Int) -> String {
        switch (newCount, removedCount) {
        case (0, 0): "0"
        case (_, 0): "+\(newCount)"
        case (0, _): "−\(removedCount)"
        default: "+\(newCount) −\(removedCount) → \(signed(newCount - removedCount))"
        }
    }

    static func attributedSummary(newCount: Int, removedCount: Int) -> AttributedString {
        func colored(_ text: String, _ color: Color) -> AttributedString {
            var fragment = AttributedString(text)
            fragment.foregroundColor = color
            return fragment
        }

        switch (newCount, removedCount) {
        case (0, 0):
            return AttributedString("0")
        case (_, 0):
            return colored("+\(newCount)", .green)
        case (0, _):
            return colored("−\(removedCount)", .red)
        default:
            let net = newCount - removedCount
            let netColor: Color = net > 0 ? .green : net < 0 ? .red : .primary
            var result = colored("+\(newCount)", .green)
            result += AttributedString(" ")
            result += colored("−\(removedCount)", .red)
            var arrow = AttributedString(" → ")
            arrow.foregroundColor = .secondary
            result += arrow
            result += colored(signed(net), netColor)
            return result
        }
    }

    static func status(newCount: Int, removedCount: Int) -> String {
        switch (newCount, removedCount) {
        case (0, 0): "No new messages"
        case (_, 0): "Ingested \(newCount) new"
        case (0, _): "Removed \(removedCount)"
        default: "Ingested \(newCount) new, removed \(removedCount)"
        }
    }

    static func companionSummary(newCount: Int, removedCount: Int) -> String {
        switch (newCount, removedCount) {
        case (0, 0): "No new this pass"
        case (_, 0): "\(newCount) new this pass"
        case (0, _): "\(removedCount) removed this pass"
        default: "\(newCount) new, \(removedCount) removed this pass"
        }
    }
}

@MainActor
struct CompanionStatusCopy {
    let session: CompanionSession
    let now: Date

    var lastIngestClock: String {
        guard let date = session.lastIngestAt else { return "—" }
        return date.formatted(date: .omitted, time: .shortened)
    }

    /// Relative age, e.g. `27m ago`. Nil when there is no ingest yet.
    var lastIngestRelative: String? {
        guard let date = session.lastIngestAt else { return nil }
        return Self.relativeAge(from: date, to: now)
    }

    var lastIngest: String {
        guard let relative = lastIngestRelative else { return lastIngestClock }
        return "\(lastIngestClock) \(relative)"
    }

    var changesWindow: String? {
        guard let start = session.lastNewSinceAt, let end = session.lastIngestAt else { return nil }
        return Self.windowCaption(from: start, to: end, now: now)
    }

    var source: String { session.source.title }

    var connectedAgent: String { session.agents.connectedAgentLabel }

    var lastAgentKind: String {
        session.agents.lastAgentRequest?.kind.rawValue ?? "—"
    }

    var lastAgentClock: String? {
        guard let entry = session.agents.lastAgentRequest else { return nil }
        return entry.at.formatted(date: .omitted, time: .shortened)
    }

    var lastAgentRelative: String? {
        guard let entry = session.agents.lastAgentRequest else { return nil }
        return Self.relativeAge(from: entry.at, to: now)
    }

    var lastAgentCall: String {
        guard let clock = lastAgentClock, let relative = lastAgentRelative else { return lastAgentKind }
        return "\(lastAgentKind) \(clock) \(relative)"
    }

    nonisolated static func relativeAge(from date: Date, to now: Date) -> String {
        let seconds = max(0, Int(now.timeIntervalSince(date)))
        if seconds < 60 { return "\(seconds)s ago" }
        let minutes = seconds / 60
        if minutes < 60 { return "\(minutes)m ago" }
        let hours = minutes / 60
        if hours < 48 { return "\(hours)h ago" }
        return "\(hours / 24)d ago"
    }

    /// Clock only on the same calendar day as `now`; `yesterday` the day before; date otherwise.
    nonisolated static func dayAwareClock(
        from date: Date,
        now: Date,
        calendar: Calendar = .current
    ) -> String {
        let clock = date.formatted(date: .omitted, time: .shortened)
        if calendar.isDate(date, inSameDayAs: now) {
            return clock
        }
        if let yesterday = calendar.date(byAdding: .day, value: -1, to: now),
           calendar.isDate(date, inSameDayAs: yesterday)
        {
            return "yesterday \(clock)"
        }
        return date.formatted(date: .abbreviated, time: .shortened)
    }

    /// Compact ingest window, e.g. `12:15–12:31 (16m)`.
    nonisolated static func windowCaption(
        from start: Date,
        to end: Date,
        now: Date,
        calendar: Calendar = .current
    ) -> String {
        let duration = compactDuration(from: start, to: end)
        if calendar.isDate(start, inSameDayAs: end) {
            let range = "\(start.formatted(date: .omitted, time: .shortened))–\(end.formatted(date: .omitted, time: .shortened))"
            if calendar.isDate(start, inSameDayAs: now) {
                return "\(range) (\(duration))"
            }
            if let yesterday = calendar.date(byAdding: .day, value: -1, to: now),
               calendar.isDate(start, inSameDayAs: yesterday)
            {
                return "yesterday \(range) (\(duration))"
            }
            return "\(start.formatted(date: .abbreviated, time: .omitted)) \(range) (\(duration))"
        }
        return "\(dayAwareClock(from: start, now: now, calendar: calendar))–\(dayAwareClock(from: end, now: now, calendar: calendar)) (\(duration))"
    }

    nonisolated private static func compactDuration(from start: Date, to end: Date) -> String {
        let seconds = max(0, Int(end.timeIntervalSince(start).rounded()))
        if seconds < 60 { return "\(seconds)s" }
        let minutes = seconds / 60
        if minutes < 60 { return "\(minutes)m" }
        let hours = minutes / 60
        let remainMinutes = minutes % 60
        if hours < 24 {
            return remainMinutes == 0 ? "\(hours)h" : "\(hours)h \(remainMinutes)m"
        }
        let days = hours / 24
        let remainHours = hours % 24
        return remainHours == 0 ? "\(days)d" : "\(days)d \(remainHours)h"
    }
}

/// Quiet time chip next to a status value.
private struct StatusTimeBadge: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.caption.weight(.medium))
            .foregroundStyle(.secondary)
            .monospacedDigit()
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(.quaternary, in: Capsule())
            .lineLimit(1)
    }
}

/// Clock plus optional relative-age chip on one line.
struct LastIngestValue: View {
    let copy: CompanionStatusCopy

    var body: some View {
        ClockAndAgeValue(clock: copy.lastIngestClock, relative: copy.lastIngestRelative)
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityLabel(copy.lastIngest)
    }
}

/// Kind plus clock and relative-age chip — same time layout as last ingest.
struct LastAgentCallValue: View {
    let copy: CompanionStatusCopy

    var body: some View {
        HStack(alignment: .center, spacing: 6) {
            Text(copy.lastAgentKind)
            if let clock = copy.lastAgentClock {
                ClockAndAgeValue(clock: clock, relative: copy.lastAgentRelative)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(copy.lastAgentCall)
    }
}

private struct ClockAndAgeValue: View {
    let clock: String
    let relative: String?

    var body: some View {
        HStack(alignment: .center, spacing: 6) {
            Text(clock)
            if let relative {
                StatusTimeBadge(text: relative)
            }
        }
        .accessibilityElement(children: .ignore)
    }
}

/// Counts plus optional window chip. Numbers stay on one line; window sits underneath.
struct IngestChangesValue: View {
    let newCount: Int
    let removedCount: Int
    let sinceLine: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(IngestPassCopy.attributedSummary(newCount: newCount, removedCount: removedCount))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.75)
                .allowsTightening(true)
            if let sinceLine {
                StatusTimeBadge(text: sinceLine)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel)
    }

    private var accessibilityLabel: String {
        let summary = IngestPassCopy.summary(newCount: newCount, removedCount: removedCount)
        guard let sinceLine else { return summary }
        return "\(summary) \(sinceLine)"
    }
}

/// Label/value snapshot used by Control Center. Menu keeps its own action buttons.
struct CompanionStatusMetrics: View {
    let session: CompanionSession

    var body: some View {
        TimelineView(.periodic(from: .now, by: 15)) { context in
            let copy = CompanionStatusCopy(session: session, now: context.date)
            VStack(alignment: .leading, spacing: 2) {
                HStack(alignment: .center, spacing: 8) {
                    Text("Last ingest")
                        .foregroundStyle(.secondary)
                        .frame(width: 118, alignment: .leading)
                    LastIngestValue(copy: copy)
                }
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text("Changes")
                        .foregroundStyle(.secondary)
                        .frame(width: 118, alignment: .leading)
                    IngestChangesValue(
                        newCount: session.lastNewCount,
                        removedCount: session.lastRemovedCount,
                        sinceLine: copy.changesWindow
                    )
                }
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
                HStack(alignment: .center, spacing: 8) {
                    Text("Last agent call")
                        .foregroundStyle(.secondary)
                        .frame(width: 118, alignment: .leading)
                    LastAgentCallValue(copy: copy)
                }
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
        case .listNew: "new"
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
        case .listNew: "envelope.badge"
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
    var compact: Bool = false

    var body: some View {
        HStack(spacing: compact ? 2 : 4) {
            Image(systemName: kind.systemImage)
                .font(compact ? .system(size: 8, weight: .semibold) : .caption2.weight(.semibold))
            Text(kind.badgeTitle)
                .font(
                    compact
                        ? .system(size: 9, weight: .semibold).monospaced()
                        : .caption.weight(.semibold).monospaced()
                )
        }
        .foregroundStyle(Color.accentColor)
        .padding(.horizontal, compact ? 5 : 7)
        .padding(.vertical, compact ? 1 : 3)
        .background(Color.accentColor.opacity(0.12), in: Capsule())
        .overlay {
            Capsule().strokeBorder(Color.accentColor.opacity(0.35), lineWidth: 0.5)
        }
        .accessibilityLabel(kind.badgeTitle)
    }
}

struct AuditOutcomeIcon: View {
    let outcome: AuditOutcome
    /// Successful call that returned zero items (search / list / new / placements).
    var emptySuccess: Bool = false

    var body: some View {
        switch outcome {
        case .ok:
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(emptySuccess ? Color.secondary : Color.green)
                .help(emptySuccess ? "Succeeded — no results" : "Succeeded")
                .accessibilityLabel(emptySuccess ? "Succeeded, no results" : "Succeeded")
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

    private var markName: String? {
        if name.compare("Cursor", options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame {
            return "CursorMark"
        }
        if name.compare("Grok", options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame
            || name.compare("Grok Bot", options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame
        {
            return "GrokMark"
        }
        return nil
    }

    var body: some View {
        Group {
            if let markName {
                markImage(markName)
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

    @ViewBuilder
    private func markImage(_ markName: String) -> some View {
        let image = Image(markName)
            .resizable()
            .interpolation(.high)
            .scaledToFit()
            .frame(width: size, height: size)
        if markName == "GrokMark" {
            image.clipShape(
                RoundedRectangle(cornerRadius: size * 0.2237, style: .continuous)
            )
        } else {
            image
        }
    }
}

struct CursorMark: View {
    var size: CGFloat = 16

    var body: some View {
        Image("CursorMark")
            .resizable()
            .interpolation(.high)
            .scaledToFit()
            .frame(width: size, height: size)
            .accessibilityHidden(true)
    }
}

struct GrokMark: View {
    var size: CGFloat = 16

    var body: some View {
        Image("GrokMark")
            .resizable()
            .interpolation(.high)
            .scaledToFit()
            .frame(width: size, height: size)
            .clipShape(
                RoundedRectangle(cornerRadius: size * 0.2237, style: .continuous)
            )
            .accessibilityHidden(true)
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

struct MessageAttachmentRow: View {
    let attachments: [MailAttachment]
    var onOpen: ((MailAttachment) -> Void)? = nil

    var body: some View {
        if attachments.isEmpty {
            EmptyView()
        } else {
            VStack(alignment: .leading, spacing: 4) {
                ForEach(attachments, id: \.self) { attachment in
                    Button {
                        onOpen?(attachment)
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "paperclip")
                                .foregroundStyle(.secondary)
                            Text(attachment.filename)
                            Text(attachment.sizeLabel)
                                .foregroundStyle(.secondary)
                            if let mimeType = attachment.mimeType {
                                Text(mimeType)
                                    .foregroundStyle(.tertiary)
                            }
                        }
                        .font(.caption)
                    }
                    .buttonStyle(.plain)
                    .disabled(onOpen == nil)
                    .help("Open with default app")
                }
            }
        }
    }
}

struct GrantFieldBadgeRow: View {
    enum LabelMode {
        case icon
        case short
        case letter
    }

    let fields: GrantFields
    var interactive: Bool = false
    var labelMode: LabelMode = .letter
    var onToggle: ((WritableKeyPath<GrantFields, Bool>) -> Void)? = nil

    private struct Item: Identifiable {
        let id: String
        let letter: String
        let short: String
        let title: String
        let systemImage: String
        let keyPath: WritableKeyPath<GrantFields, Bool>
    }

    private static let items: [Item] = [
        Item(id: "subject", letter: "S", short: "Subj", title: "Subject", systemImage: "text.alignleft", keyPath: \.subject),
        Item(id: "from", letter: "F", short: "From", title: "From", systemImage: "envelope", keyPath: \.from),
        Item(id: "to", letter: "T", short: "To", title: "To", systemImage: "tray.and.arrow.down", keyPath: \.to),
        Item(id: "cc", letter: "Cc", short: "Cc", title: "Cc", systemImage: "person.2", keyPath: \.cc),
        Item(id: "date", letter: "D", short: "Date", title: "Date & Time", systemImage: "calendar", keyPath: \.date),
        Item(id: "body", letter: "B", short: "Body", title: "Body", systemImage: "doc.plaintext", keyPath: \.body),
        Item(id: "att", letter: "A", short: "Att", title: "Attachment names", systemImage: "paperclip", keyPath: \.attachmentMetadata),
        Item(id: "bytes", letter: "C", short: "File", title: "Attachment content", systemImage: "doc", keyPath: \.attachmentContent),
    ]

    var body: some View {
        HStack(spacing: 2) {
            ForEach(Self.items) { item in
                let on = fields[keyPath: item.keyPath]
                if interactive, let onToggle {
                    Button {
                        onToggle(item.keyPath)
                    } label: {
                        compactBadge(item, on: on)
                    }
                    .buttonStyle(.plain)
                    .help(item.title)
                    .accessibilityLabel(item.title)
                } else {
                    compactBadge(item, on: on)
                        .help(item.title)
                        .accessibilityLabel(item.title)
                }
            }
        }
    }

    private func compactBadge(_ item: Item, on: Bool) -> some View {
        HStack(spacing: 2) {
            Image(systemName: item.systemImage)
                .font(.system(size: 8, weight: on ? .medium : .regular))
            if let text = labelText(item) {
                Text(text)
                    .font(.system(size: 8, weight: on ? .medium : .regular))
                    .strikethrough(!on, color: Color.secondary.opacity(0.45))
            }
        }
        .foregroundStyle(on ? Color.accentColor : Color.secondary.opacity(0.55))
        .padding(.horizontal, labelMode == .icon ? 5 : 4)
        .frame(height: 14)
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
    }

    private func labelText(_ item: Item) -> String? {
        switch labelMode {
        case .icon: nil
        case .short: item.short
        case .letter: item.letter
        }
    }
}

enum HeadersOnlyStyle {
    static let text = Color(.systemTeal).opacity(0.85)
    static let fill = Color(.systemTeal).opacity(0.08)
}

struct MessageAccessCard: View {
    let session: CompanionSession
    let ref: AuditMessageRef
    var omitsBody: Bool = false
    var showsFieldBadges: Bool = true
    var attachmentContentDetail: String = "none in this response"

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            SourceChip(session: session, accountID: ref.accountID, placement: ref.placement)
            if showsFieldBadges {
                GrantFieldBadgeRow(fields: ref.fields)
            }
            subjectPreview
            if ref.fields.from {
                AddressLine(label: "From", raw: ref.from)
            } else {
                previewRow("From", ref.from, false)
            }
            if ref.fields.to {
                AddressLine(label: "To", raw: ref.to)
            } else {
                previewRow("To", ref.to, false)
            }
            if ref.fields.cc {
                AddressLine(label: "Cc", raw: ref.cc)
            } else {
                previewRow("Cc", ref.cc, false)
            }
            previewRow(
                "Date & Time",
                AccessLogFormat.compactMailDate(ref.date) ?? ref.date,
                ref.fields.date
            )
            Divider()
            Text("Body")
                .font(.caption)
                .foregroundStyle(.secondary)
            bodyPreview
            Divider()
            HStack(alignment: .top, spacing: 6) {
                attachmentColumn("Attachment Info", granted: ref.fields.attachmentMetadata) {
                    if ref.attachments.isEmpty {
                        attachmentTile(detail: "none in this response")
                    } else {
                        ForEach(Array(ref.attachments.enumerated()), id: \.offset) { _, attachment in
                            attachmentTile(detail: "\(attachment.filename) · \(attachment.sizeLabel)")
                        }
                    }
                }
                attachmentColumn("Attachment Content", granted: ref.fields.attachmentContent) {
                    attachmentTile(detail: attachmentContentDetail)
                }
            }
        }
        .padding(10)
        .overlay {
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(Color.secondary.opacity(0.2), lineWidth: 1)
        }
    }

    @ViewBuilder
    private var subjectPreview: some View {
        leakGuardRow(
            label: "Subject",
            text: ref.subject.isEmpty ? "(no subject)" : ref.subject,
            fieldGranted: ref.fields.subject,
            access: effectiveSubjectAccess,
            original: ref.subjectOriginal,
            deniedPlaceholder: ref.subject.isEmpty ? "(no subject)" : ref.subject
        )
    }

    @ViewBuilder
    private var bodyPreview: some View {
        if omitsBody, effectiveBodyAccess != .notGranted {
            omittedBodyPreview
        } else if effectiveBodyAccess == .notGranted {
            HatchDeniedLabel(placeholder: "Body / snippet", fixedHeight: 112)
                .frame(maxWidth: .infinity)
                .padding(10)
                .frame(maxWidth: .infinity, minHeight: 132, alignment: .topLeading)
                .background(Color.secondary.opacity(0.06))
                .clipShape(RoundedRectangle(cornerRadius: 8))
        } else {
            bodyFieldContent
                .frame(maxWidth: .infinity, minHeight: 132, alignment: .topLeading)
                .padding(10)
                .background(Color.secondary.opacity(0.06))
                .clipShape(RoundedRectangle(cornerRadius: 8))
        }
    }

    @ViewBuilder
    private var bodyFieldContent: some View {
        switch effectiveBodyAccess {
        case .granted:
            Text(ref.bodySnippet)
                .font(.caption)
                .textSelection(.enabled)
        case .notAvailable:
            Text("not available")
                .font(.caption)
                .foregroundStyle(.secondary)
                .italic()
        case .notGranted:
            HatchDeniedLabel(placeholder: "Body / snippet")
        case .sanitized:
            SanitizedFieldText(
                text: ref.bodySnippet,
                original: ref.bodyOriginal,
                rules: ref.sanitizedRules,
                stealth: ref.stealth == true
            )
        case .withheldConfidential:
            WithheldLabel(original: ref.bodyOriginal, rules: ref.sanitizedRules)
        }
    }

    /// Agent JSON may report stealth substitutes as `granted`; Access Log still marks them.
    private var effectiveBodyAccess: AuditBodyAccess {
        if ref.bodyAccess == .granted,
           ref.stealth == true,
           (ref.bodyOriginal != nil || ref.displayLeakDetections.contains { $0.field == .body })
        {
            return .sanitized
        }
        return ref.bodyAccess
    }

    private var effectiveSubjectAccess: AuditBodyAccess {
        let access = ref.subjectAccess ?? .granted
        if access == .granted,
           ref.stealth == true,
           (ref.subjectOriginal != nil || ref.displayLeakDetections.contains { $0.field == .subject })
        {
            return .sanitized
        }
        return access
    }

    @ViewBuilder
    private func leakGuardRow(
        label: String,
        text: String,
        fieldGranted: Bool,
        access: AuditBodyAccess,
        original: String?,
        deniedPlaceholder: String
    ) -> some View {
        HStack(alignment: .top, spacing: 6) {
            Text("\(label):")
                .fontWeight(.light)
                .foregroundStyle(.secondary)
            if !fieldGranted {
                HatchDeniedLabel(placeholder: deniedPlaceholder)
            } else {
                switch access {
                case .granted, .notAvailable:
                    Text(text)
                        .foregroundStyle(text.hasPrefix("(") ? .secondary : .primary)
                        .textSelection(.enabled)
                case .notGranted:
                    HatchDeniedLabel(placeholder: deniedPlaceholder)
                case .sanitized:
                    SanitizedFieldText(
                        text: text,
                        original: original,
                        rules: ref.sanitizedRules,
                        stealth: ref.stealth == true
                    )
                case .withheldConfidential:
                    WithheldLabel(original: original, rules: ref.sanitizedRules)
                }
            }
        }
        .font(.caption)
    }

    private var omittedBodyPreview: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("Not included")
                .font(.caption.weight(.medium))
                .foregroundStyle(HeadersOnlyStyle.text)
            Text("Search and list return headers only. Use get for body.")
                .font(.system(size: 10))
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(8)
        .background(HeadersOnlyStyle.fill)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .help("Search and list do not include message body")
    }

    private func previewRow(_ label: String, _ value: String, _ granted: Bool, empty: String = " ") -> some View {
        HStack(alignment: .top, spacing: 6) {
            Text("\(label):")
                .fontWeight(.light)
                .foregroundStyle(.secondary)
            if granted {
                Text(value.isEmpty ? empty : value)
                    .foregroundStyle(value.isEmpty ? .secondary : .primary)
                    .textSelection(.enabled)
            } else {
                HatchDeniedLabel(placeholder: value.isEmpty ? empty : value)
            }
        }
        .font(.caption)
    }

    private func attachmentColumn<Content: View>(
        _ title: String,
        granted: Bool,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            if granted {
                content()
            } else {
                attachmentTile(detail: nil)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func attachmentTile(detail: String?) -> some View {
        HStack(alignment: .center, spacing: 6) {
            Image(systemName: "paperclip")
                .font(.caption)
                .foregroundStyle(.secondary)
            Group {
                if let detail {
                    Text(detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                } else {
                    HatchDeniedLabel(fixedHeight: 18)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(6)
        .frame(maxWidth: .infinity, minHeight: 32, alignment: .leading)
        .background(Color.secondary.opacity(0.05))
        .cornerRadius(6)
    }
}

enum HatchDeniedStyle {
    static let stripe = Color(.systemRed).opacity(0.28)
    static let fill = Color(.systemRed).opacity(0.06)
    static let lock = Color(.systemRed).opacity(0.52)
    static let legend = Color(.systemRed).opacity(0.72)
}

struct LockedFieldsLegend: View {
    var body: some View {
        HStack(alignment: .center, spacing: 4) {
            HatchLockIcon()
            Text("Locked. Grant does not allow the agent to read this field.")
                .font(.system(size: 10))
        }
        .foregroundStyle(HatchDeniedStyle.legend)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Locked. Grant does not allow the agent to read this field.")
    }
}

struct HatchLockIcon: View {
    var body: some View {
        Image(systemName: "lock.fill")
            .font(.system(size: 9, weight: .semibold))
            .foregroundStyle(HatchDeniedStyle.lock)
            .accessibilityHidden(true)
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
            HatchLockIcon()
        }
        .clipShape(RoundedRectangle(cornerRadius: 4))
        .accessibilityLabel("Locked")
        .help("Locked — grant does not allow this field")
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
                with: .color(HatchDeniedStyle.stripe),
                lineWidth: 1
            )
            context.fill(
                Path(CGRect(origin: .zero, size: size)),
                with: .color(HatchDeniedStyle.fill)
            )
        }
    }
}

// MARK: - Leak guard access log visuals

struct AccessLogLeakHitBadge: View {
    let count: Int
    /// Collapsed / list: shield chip + count. Expanded: `{shield} leak` chip + count.
    var compact: Bool = false

    var body: some View {
        HStack(spacing: 3) {
            HStack(spacing: compact ? 0 : 3) {
                ZStack {
                    Text("L")
                        .font(.system(size: 8, weight: .semibold))
                        .opacity(0)
                    Image(systemName: "shield.fill")
                        .font(.system(size: 9, weight: .medium))
                    Text("L")
                        .font(.system(size: 5.5, weight: .bold))
                        .offset(y: 0.5)
                }
                if !compact {
                    Text("leak")
                        .font(.system(size: 9, weight: .semibold))
                }
            }
            .foregroundStyle(WithheldStyle.text)
            .padding(.horizontal, compact ? 4 : 5)
            .frame(height: 14)
            .background(Capsule().fill(WithheldStyle.fill))
            .overlay {
                Capsule().strokeBorder(WithheldStyle.border, lineWidth: 0.5)
            }

            Text("\(count)")
                .font(.caption2.weight(.semibold).monospacedDigit())
                .foregroundStyle(WithheldStyle.text)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            "Leak guard detected \(count) part\(count == 1 ? "" : "s")"
        )
        .help("Leak guard detected \(count) sensitive part\(count == 1 ? "" : "s")")
        .layoutPriority(1)
    }
}

struct LeakGuardDetectionsList: View {
    let detections: [AuditLeakDetection]

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(Array(detections.enumerated()), id: \.offset) { _, detection in
                detectionRow(detection)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(WithheldStyle.fill, in: RoundedRectangle(cornerRadius: 6))
        .overlay {
            RoundedRectangle(cornerRadius: 6)
                .strokeBorder(WithheldStyle.border, lineWidth: 0.5)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Leak guard detections")
    }

    @ViewBuilder
    private func detectionRow(_ detection: AuditLeakDetection) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 5) {
                Text(fieldTitle(detection.field))
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(WithheldStyle.text)
                Text("·")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                Text(detection.label)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Text("·")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                Text(modeTitle(detection))
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(WithheldStyle.text)
                Spacer(minLength: 0)
            }
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(displayOriginal(detection))
                    .font(.caption.monospaced())
                    .foregroundStyle(.primary)
                    .lineLimit(2)
                    .truncationMode(.middle)
                    .textSelection(.enabled)
                Text("→")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.tertiary)
                replacementView(detection)
                Spacer(minLength: 0)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityText(detection))
        .help(helpText(detection))
    }

    private func fieldTitle(_ field: AuditLeakDetection.Field) -> String {
        switch field {
        case .subject: "Subject"
        case .body: "Body"
        }
    }

    private func modeTitle(_ detection: AuditLeakDetection) -> String {
        switch detection.disposition {
        case .redacted:
            return "redacted"
        case .replaced:
            return detection.discloseToAgent ? "replaced" : "stealth replace"
        case .withheld:
            return "withheld"
        }
    }

    private func displayOriginal(_ detection: AuditLeakDetection) -> String {
        let text = detection.original.trimmingCharacters(in: .whitespacesAndNewlines)
        return text.isEmpty ? detection.label : text
    }

    @ViewBuilder
    private func replacementView(_ detection: AuditLeakDetection) -> some View {
        switch detection.disposition {
        case .redacted:
            RedactedTokenChip()
        case .replaced:
            Text(detection.replacement.isEmpty ? "…" : detection.replacement)
                .font(.caption.monospaced())
                .foregroundStyle(WithheldStyle.text)
                .lineLimit(2)
                .truncationMode(.middle)
                .textSelection(.enabled)
        case .withheld:
            WithheldLabel(rules: [detection.label])
        }
    }

    private func accessibilityText(_ detection: AuditLeakDetection) -> String {
        let whereField = fieldTitle(detection.field)
        let mode = modeTitle(detection)
        let original = displayOriginal(detection)
        switch detection.disposition {
        case .redacted:
            return "\(whereField), \(detection.label), \(mode): \(original) redacted"
        case .replaced:
            return "\(whereField), \(detection.label), \(mode): \(original) to \(detection.replacement)"
        case .withheld:
            return "\(whereField), \(detection.label), \(mode): \(original)"
        }
    }

    private func helpText(_ detection: AuditLeakDetection) -> String {
        "\(fieldTitle(detection.field)) · \(detection.label) · \(modeTitle(detection))"
    }
}

/// Compact hatch chip for `[REDACTED]` in leak-detection rows.
struct RedactedTokenChip: View {
    var body: some View {
        Text("[REDACTED]")
            .font(.system(size: 9, weight: .bold).monospaced())
            .foregroundStyle(HatchDeniedStyle.lock)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background {
                HatchPattern().opacity(0.95)
            }
            .overlay {
                RoundedRectangle(cornerRadius: 3)
                    .strokeBorder(HatchDeniedStyle.stripe, lineWidth: 0.5)
            }
            .clipShape(RoundedRectangle(cornerRadius: 3))
            .accessibilityLabel("Redacted")
    }
}

/// Leak guard chrome — violet, not warning orange / grant red / success green / accent blue.
enum LeakGuardStyle {
    static let ink = Color.purple
    static let text = Color.purple.opacity(0.88)
    static let fill = Color.purple.opacity(0.12)
    static let fillStrong = Color.purple.opacity(0.15)
    static let border = Color.purple.opacity(0.38)
    static let borderSoft = Color.purple.opacity(0.25)
    static let legend = Color.purple.opacity(0.78)
}

enum WithheldStyle {
    static let text = LeakGuardStyle.text
    static let fill = LeakGuardStyle.fill
    static let border = LeakGuardStyle.border
    static let legend = LeakGuardStyle.legend
}

struct WithheldLabel: View {
    var original: String? = nil
    var rules: [String]? = nil

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: "eye.slash.fill")
                .font(.system(size: 9, weight: .semibold))
            Text("Withheld")
                .font(.caption.weight(.semibold))
        }
        .foregroundStyle(WithheldStyle.text)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(WithheldStyle.fill, in: RoundedRectangle(cornerRadius: 4))
        .overlay {
            RoundedRectangle(cornerRadius: 4)
                .strokeBorder(WithheldStyle.border, lineWidth: 0.5)
        }
        .accessibilityLabel("Withheld by leak guard")
        .help(tooltip)
    }

    private var tooltip: String {
        var parts = ["Whole field withheld — leak guard blocked outbound content."]
        if let rules, !rules.isEmpty {
            parts.append("Rules: \(rules.joined(separator: ", "))")
        }
        if let original, !original.isEmpty {
            parts.append("Original: \(original)")
        }
        return parts.joined(separator: "\n")
    }
}

enum SanitizedFieldStyle {
    static let fill = Color.purple.opacity(0.14)
    static let legend = LeakGuardStyle.legend
}

struct SanitizedFieldText: View {
    let text: String
    var original: String? = nil
    var rules: [String]? = nil
    var stealth: Bool = false
    var font: Font = .caption

    var body: some View {
        Text(displayText)
            .font(font)
            .foregroundStyle(displayText.isEmpty ? .secondary : .primary)
            .padding(.horizontal, hasSanitizationMarker ? 4 : 0)
            .padding(.vertical, hasSanitizationMarker ? 2 : 0)
            .background {
                if hasSanitizationMarker {
                    RoundedRectangle(cornerRadius: 3)
                        .fill(SanitizedFieldStyle.fill)
                }
            }
            .textSelection(.enabled)
            .help(tooltip)
            .accessibilityLabel(accessibilityLabel)
    }

    private var displayText: String {
        text.isEmpty ? "(empty)" : text
    }

    private var hasSanitizationMarker: Bool {
        if let original, original != text { return true }
        if stealth { return true }
        if let rules, !rules.isEmpty { return true }
        return false
    }

    private var tooltip: String {
        var parts: [String] = []
        if stealth {
            parts.append("Stealth replace — agent saw substituted text.")
        }
        if let original, original != text {
            parts.append("Original: \(original)")
        }
        if let rules, !rules.isEmpty {
            parts.append("Rules: \(rules.joined(separator: ", "))")
        }
        if parts.isEmpty {
            parts.append("Sanitized on device before the agent received this field.")
        }
        return parts.joined(separator: "\n")
    }

    private var accessibilityLabel: String {
        var label = displayText
        if hasSanitizationMarker {
            label += ". Sanitized"
        }
        if let original, original != text {
            label += ". Original: \(original)"
        }
        return label
    }
}

struct SanitizedFieldsLegend: View {
    var body: some View {
        HStack(alignment: .center, spacing: 4) {
            Image(systemName: "text.line.first.and.arrowtriangle.forward")
                .font(.system(size: 9, weight: .semibold))
            Text("Sanitized. Purple tint — hover for original text and matching rules.")
                .font(.system(size: 10))
        }
        .foregroundStyle(SanitizedFieldStyle.legend)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            "Sanitized. Purple tint. Hover for original text and matching rules."
        )
    }
}
