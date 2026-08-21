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
