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
    /// When set (e.g. `1` for a ViewThatFits side-by-side candidate), the badge refuses to wrap.
    var lineLimit: Int? = nil

    var body: some View {
        Text(email)
            .textSelection(.enabled)
            .lineLimit(lineLimit)
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
    /// WebKit `pageZoom` for HTML; plain text scales font when ≠ 1. Companion stays at 1.
    var pageZoom: CGFloat = 1
    /// Ask canvas: pad MIME HTML so the first line is not flush-clipped at the top.
    var ensureReadableInsets: Bool = false

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
                HTMLMailView(
                    html: Self.documentHTML(html),
                    pageZoom: pageZoom,
                    // Ask preview owns zoom via pageZoom; Companion keeps pinch magnify.
                    allowsMagnification: !ensureReadableInsets && abs(pageZoom - 1) < 0.001,
                    ensureReadableInsets: ensureReadableInsets
                )
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                switch readBody {
                case .text(let text):
                    if ensureReadableInsets {
                        // Ask canvas: AppKit-owned scroll (`NSTextView.scrollableTextView`).
                        // Intrinsic LinkAwareBodyText + sizeThatFits expands past the pane and
                        // clips the top so scroll-up cannot reach the first lines.
                        ScrollableLinkAwareBodyText(
                            attributed: Self.prettyAttributed(text),
                            fontScale: pageZoom
                        )
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else {
                        LinkAwareBodyText(attributed: Self.prettyAttributed(text), fontScale: pageZoom)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
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
          html { margin: 0; }
          body {
            font: -apple-system-body;
            font-family: -apple-system, BlinkMacSystemFont, sans-serif;
            margin: 0;
            padding: 12px;
            background: transparent;
            overflow-wrap: anywhere;
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
    var pageZoom: CGFloat = 1
    var allowsMagnification: Bool = true
    /// Inject body padding so flush MIME HTML does not clip the first line (Ask preview).
    var ensureReadableInsets: Bool = false

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.defaultWebpagePreferences.allowsContentJavaScript = true
        if ensureReadableInsets {
            let pad = WKUserScript(
                source: """
                (function () {
                  if (document.getElementById('mailgent-preview-pad')) return;
                  var s = document.createElement('style');
                  s.id = 'mailgent-preview-pad';
                  s.textContent = 'html{margin:0!important;}body{margin:0!important;padding:12px!important;box-sizing:border-box!important;}';
                  (document.head || document.documentElement).appendChild(s);
                })();
                """,
                injectionTime: .atDocumentEnd,
                forMainFrameOnly: true
            )
            config.userContentController.addUserScript(pad)
        }
        let webView = WKWebView(frame: .zero, configuration: config)
        webView.setValue(false, forKey: "drawsBackground")
        webView.clipsToBounds = true
        webView.navigationDelegate = context.coordinator
        webView.allowsMagnification = allowsMagnification
        context.coordinator.ensureReadableInsets = ensureReadableInsets
        context.coordinator.applyZoom(pageZoom, to: webView)
        return webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        webView.allowsMagnification = allowsMagnification
        context.coordinator.ensureReadableInsets = ensureReadableInsets
        if abs(context.coordinator.appliedZoom - pageZoom) > 0.001 {
            context.coordinator.applyZoom(pageZoom, to: webView)
            context.coordinator.scrollToTop(webView)
        }
        guard context.coordinator.loadedHTML != html else { return }
        context.coordinator.loadedHTML = html
        webView.loadHTMLString(html, baseURL: nil)
    }

    final class Coordinator: NSObject, WKNavigationDelegate {
        var loadedHTML: String?
        var appliedZoom: CGFloat = 1
        var ensureReadableInsets = false

        func webView(
            _ webView: WKWebView,
            decidePolicyFor navigationAction: WKNavigationAction,
            decisionHandler: @escaping @MainActor @Sendable (WKNavigationActionPolicy) -> Void
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

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation) {
            // Re-apply after navigation replaces the document (CSS zoom is per-document).
            applyZoom(appliedZoom, to: webView)
            scrollToTop(webView)
        }

        func applyZoom(_ zoom: CGFloat, to webView: WKWebView) {
            appliedZoom = zoom
            // Prefer WebKit pageZoom: CSS zoom on documentElement breaks scroll at >100%
            // and can paint outside the view (covering the Ask zoom strip).
            // Readable insets (padding script) keep the first line reachable.
            if ensureReadableInsets {
                webView.evaluateJavaScript(
                    "document.documentElement.style.zoom='';"
                ) { _, _ in }
            }
            webView.pageZoom = zoom
            if !webView.allowsMagnification {
                webView.magnification = 1
            }
        }

        func scrollToTop(_ webView: WKWebView) {
            webView.evaluateJavaScript(
                """
                window.scrollTo(0, 0);
                if (document.documentElement) document.documentElement.scrollTop = 0;
                if (document.body) document.body.scrollTop = 0;
                """
            ) { _, _ in }
            // AppKit scroll view can retain a non-zero origin after zoom/layout.
            DispatchQueue.main.async {
                Self.resetAppKitScroll(webView)
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                Self.resetAppKitScroll(webView)
            }
        }

        private static func resetAppKitScroll(_ webView: WKWebView) {
            var scrollViews: [NSScrollView] = []
            if let enclosing = webView.enclosingScrollView {
                scrollViews.append(enclosing)
            }
            func collect(from view: NSView) {
                if let scroll = view as? NSScrollView {
                    scrollViews.append(scroll)
                }
                for child in view.subviews {
                    collect(from: child)
                }
            }
            collect(from: webView)
            for scrollView in scrollViews {
                scrollView.contentView.scroll(to: .zero)
                scrollView.reflectScrolledClipView(scrollView.contentView)
            }
        }
    }
}

/// AppKit text view so link hover shows the pointing-hand cursor (SwiftUI `Text` does not).
/// Intrinsic height via `sizeThatFits` — for Companion plain bodies inside a SwiftUI `ScrollView`.
private struct LinkAwareBodyText: NSViewRepresentable {
    let attributed: AttributedString
    var fontScale: CGFloat = 1

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
        textView.linkTextAttributes = Self.linkAttributes
        textView.delegate = context.coordinator
        return textView
    }

    func updateNSView(_ textView: NSTextView, context: Context) {
        textView.textStorage?.setAttributedString(Self.scaledAttributedString(attributed, fontScale: fontScale))
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

    fileprivate static let linkAttributes: [NSAttributedString.Key: Any] = [
        .foregroundColor: NSColor.linkColor,
        .underlineStyle: NSUnderlineStyle.single.rawValue,
        .cursor: NSCursor.pointingHand,
    ]

    fileprivate static func scaledAttributedString(
        _ attributed: AttributedString,
        fontScale: CGFloat
    ) -> NSAttributedString {
        let bridged = NSMutableAttributedString(attributedString: NSAttributedString(attributed))
        let base = NSFont.preferredFont(forTextStyle: .body)
        let size = max(9, base.pointSize * fontScale)
        let font = NSFont(descriptor: base.fontDescriptor, size: size) ?? base
        bridged.addAttribute(.font, value: font, range: NSRange(location: 0, length: bridged.length))
        return bridged
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

/// Ask preview plain body: Apple’s `NSTextView.scrollableTextView()` fills the pane and owns scrolling.
private struct ScrollableLinkAwareBodyText: NSViewRepresentable {
    let attributed: AttributedString
    var fontScale: CGFloat = 1

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSTextView.scrollableTextView()
        scrollView.drawsBackground = false
        scrollView.borderType = .noBorder
        scrollView.hasHorizontalScroller = false
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.automaticallyAdjustsContentInsets = false
        scrollView.contentInsets = .init(top: 8, left: 10, bottom: 8, right: 10)
        scrollView.scrollerInsets = .init(top: 0, left: 0, bottom: 0, right: 0)

        guard let textView = scrollView.documentView as? NSTextView else { return scrollView }
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
        textView.minSize = .zero
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.linkTextAttributes = LinkAwareBodyText.linkAttributes
        textView.delegate = context.coordinator
        apply(attributed, fontScale: fontScale, to: textView, scrollView: scrollView, resetScroll: true)
        context.coordinator.loadedScale = fontScale
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = scrollView.documentView as? NSTextView else { return }
        let scaleChanged = abs(context.coordinator.loadedScale - fontScale) > 0.001
        let textChanged = context.coordinator.loadedHash != attributedHash
        guard scaleChanged || textChanged else { return }
        context.coordinator.loadedScale = fontScale
        context.coordinator.loadedHash = attributedHash
        apply(attributed, fontScale: fontScale, to: textView, scrollView: scrollView, resetScroll: true)
    }

    private var attributedHash: Int {
        var hasher = Hasher()
        hasher.combine(String(attributed.characters))
        hasher.combine(fontScale)
        return hasher.finalize()
    }

    private func apply(
        _ attributed: AttributedString,
        fontScale: CGFloat,
        to textView: NSTextView,
        scrollView: NSScrollView,
        resetScroll: Bool
    ) {
        textView.textStorage?.setAttributedString(
            LinkAwareBodyText.scaledAttributedString(attributed, fontScale: fontScale)
        )
        guard resetScroll else { return }
        // Pin to the document top after load/zoom (AppKit scroll views can keep a stale origin).
        DispatchQueue.main.async {
            textView.scrollRangeToVisible(NSRange(location: 0, length: 0))
            scrollView.contentView.scroll(to: .zero)
            scrollView.reflectScrolledClipView(scrollView.contentView)
        }
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        var loadedHash: Int = 0
        var loadedScale: CGFloat = 1

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

/// Bordered icon+label control for non-destructive handoffs (see `docs/ui-inventory.md` → SecondaryAction).
/// Ask G flush family: 20pt height, 11pt label, 6pt radius, no track gutter.
@MainActor
enum SecondaryActionMetrics {
    static let controlHeight: CGFloat = 20
    static let cornerRadius: CGFloat = 6
    static let labelFont = Font.system(size: 11, weight: .regular)
    /// Subtle selected fill (include-in-rule `.on`).
    static let selectedFill = Color(red: 214 / 255, green: 233 / 255, blue: 255 / 255)
    static let selectedBorder = Color(red: 126 / 255, green: 182 / 255, blue: 255 / 255)

    static let expandAnimation = Animation.spring(response: 0.34, dampingFraction: 0.86)
}

struct SecondaryActionButton: View {
    let title: String
    let action: () -> Void
    /// When true, label stays visible (Ask dialog). Default: icon-only until hover.
    var alwaysExpanded: Bool = false
    /// Subtle selected chrome (include-in-rule).
    var isOn: Bool = false
    /// Fixed-width slot; label expands left as overlay (no envelope value reflow).
    var expandLeadingOverlay: Bool = false
    private let icon: AnyView

    @State private var isHovered = false

    static var controlHeight: CGFloat { SecondaryActionMetrics.controlHeight }

    init(
        title: String,
        systemImage: String,
        alwaysExpanded: Bool = false,
        isOn: Bool = false,
        expandLeadingOverlay: Bool = false,
        action: @escaping () -> Void
    ) {
        self.title = title
        self.action = action
        self.alwaysExpanded = alwaysExpanded
        self.isOn = isOn
        self.expandLeadingOverlay = expandLeadingOverlay
        self.icon = AnyView(SecondaryActionSystemGlyph(systemImage: systemImage))
    }

    init(
        title: String,
        alwaysExpanded: Bool = false,
        isOn: Bool = false,
        expandLeadingOverlay: Bool = false,
        action: @escaping () -> Void,
        @ViewBuilder icon: () -> some View
    ) {
        self.title = title
        self.action = action
        self.alwaysExpanded = alwaysExpanded
        self.isOn = isOn
        self.expandLeadingOverlay = expandLeadingOverlay
        self.icon = AnyView(icon())
    }

    private var showsLabel: Bool { alwaysExpanded || isHovered }

    var body: some View {
        if expandLeadingOverlay {
            slotOverlayBody
        } else {
            standardBody
        }
    }

    private var standardBody: some View {
        Button(action: action) {
            faceContent
                .padding(.horizontal, showsLabel ? 8 : 4)
                .frame(minWidth: SecondaryActionMetrics.controlHeight - 2, maxHeight: .infinity)
        }
        .buttonStyle(SecondaryActionButtonStyle(isOn: isOn))
        .frame(height: SecondaryActionMetrics.controlHeight)
        .fixedSize(horizontal: true, vertical: true)
        .onHover { hovering in
            guard !alwaysExpanded else { return }
            withAnimation(SecondaryActionMetrics.expandAnimation) {
                isHovered = hovering
            }
        }
        .help(title)
        .accessibilityLabel(title)
        .accessibilityAddTraits(isOn ? .isSelected : [])
    }

    /// Icon-only footprint; hovered label grows to the left over neighbors.
    private var slotOverlayBody: some View {
        ZStack(alignment: .trailing) {
            Color.clear
                .frame(
                    width: SecondaryActionMetrics.controlHeight,
                    height: SecondaryActionMetrics.controlHeight
                )
            Button(action: action) {
                faceContent
                    .padding(.horizontal, showsLabel ? 8 : 4)
                    .frame(
                        minWidth: SecondaryActionMetrics.controlHeight - 2,
                        maxHeight: .infinity
                    )
            }
            .buttonStyle(SecondaryActionButtonStyle(isOn: isOn))
            .frame(height: SecondaryActionMetrics.controlHeight)
            .fixedSize(horizontal: true, vertical: true)
            .zIndex(showsLabel ? 4 : 1)
        }
        .frame(
            width: SecondaryActionMetrics.controlHeight,
            height: SecondaryActionMetrics.controlHeight,
            alignment: .trailing
        )
        .onHover { hovering in
            withAnimation(SecondaryActionMetrics.expandAnimation) {
                isHovered = hovering
            }
        }
        .help(title)
        .accessibilityLabel(title)
        .accessibilityAddTraits(isOn ? .isSelected : [])
    }

    private var faceContent: some View {
        HStack(spacing: showsLabel ? 5 : 0) {
            icon
                .frame(width: 11, height: 11)
                .foregroundStyle(isOn ? Color.accentColor : Color.secondary)
            Text(title)
                .font(SecondaryActionMetrics.labelFont)
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: true)
                .opacity(showsLabel ? 1 : 0)
                .frame(maxWidth: showsLabel ? 280 : 0, alignment: .leading)
                .clipped()
        }
    }
}

/// Single SF Symbol glyph for secondary actions (Preview, etc.).
struct SecondaryActionSystemGlyph: View {
    let systemImage: String

    var body: some View {
        Image(systemName: systemImage)
            .font(.system(size: 10, weight: .regular))
            .symbolRenderingMode(.hierarchical)
    }
}

/// Flush AND/OR (or similar) chip matching Ask G control height / radius.
struct AskFlushSegmentButton: View {
    let title: String
    var isOn: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 11, weight: .semibold))
                .padding(.horizontal, 10)
                .frame(height: SecondaryActionMetrics.controlHeight)
                .foregroundStyle(isOn ? Color.white : Color.secondary)
                .background(
                    RoundedRectangle(cornerRadius: SecondaryActionMetrics.cornerRadius, style: .continuous)
                        .fill(isOn ? Color.accentColor : Color(nsColor: .controlBackgroundColor))
                )
                .overlay {
                    RoundedRectangle(cornerRadius: SecondaryActionMetrics.cornerRadius, style: .continuous)
                        .strokeBorder(
                            isOn ? Color.accentColor : Color.secondary.opacity(0.32),
                            lineWidth: 1
                        )
                }
        }
        .buttonStyle(.plain)
    }
}

/// Ghost Close / secondary text button in the Ask flush family.
struct AskFlushGhostButton: View {
    let title: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 11, weight: .medium))
                .padding(.horizontal, 8)
                .frame(height: SecondaryActionMetrics.controlHeight)
                .foregroundStyle(Color.primary)
                .background(
                    RoundedRectangle(cornerRadius: SecondaryActionMetrics.cornerRadius, style: .continuous)
                        .fill(Color(nsColor: .controlBackgroundColor))
                )
                .overlay {
                    RoundedRectangle(cornerRadius: SecondaryActionMetrics.cornerRadius, style: .continuous)
                        .strokeBorder(Color.secondary.opacity(0.32), lineWidth: 1)
                }
        }
        .buttonStyle(.plain)
    }
}

private struct SecondaryActionButtonStyle: ButtonStyle {
    var isOn: Bool = false

    func makeBody(configuration: Configuration) -> some View {
        let border = isOn
            ? SecondaryActionMetrics.selectedBorder
            : Color.secondary.opacity(configuration.isPressed ? 0.42 : 0.32)
        let fill = isOn
            ? SecondaryActionMetrics.selectedFill
            : Color(nsColor: .controlBackgroundColor)
        return configuration.label
            .background {
                RoundedRectangle(cornerRadius: SecondaryActionMetrics.cornerRadius, style: .continuous)
                    .fill(fill)
            }
            .overlay {
                RoundedRectangle(cornerRadius: SecondaryActionMetrics.cornerRadius, style: .continuous)
                    .strokeBorder(border, lineWidth: 1)
            }
            .opacity(configuration.isPressed ? 0.92 : 1)
    }
}

#Preview("SecondaryAction vs Formatted") {
    struct Host: View {
        @State private var view: AccessLogSideView = .formatted
        @State private var jsonStyle: AccessLogJSONStyle = .pretty

        var body: some View {
            VStack(alignment: .leading, spacing: 16) {
                Text("Secondary actions — icon only; hover expands label")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                HStack(spacing: 6) {
                    SecondaryActionButton(title: "Preview", systemImage: "eye") {}
                    SecondaryActionButton(title: "Open in Apple Mail") {
                        // no-op preview
                    } icon: {
                        OpenInMailGlyph()
                    }
                }

                Divider()

                Text("Mode chrome (img2)")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                AccessLogModeHeader(title: "Response", view: $view, jsonStyle: $jsonStyle)

                Divider()

                Text("Side by side (hover Preview)")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                HStack(alignment: .center, spacing: 8) {
                    SecondaryActionButton(title: "Preview", systemImage: "eye") {}
                    Picker("Formatted", selection: .constant(true)) {
                        Text("Formatted").tag(true)
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .controlSize(.small)
                    .fixedSize()
                }
            }
            .padding(20)
            .frame(width: 520, alignment: .leading)
            .background(Color(nsColor: .windowBackgroundColor))
        }
    }

    return Host()
}

struct OpenInMailButton: View {
    var session: CompanionSession
    /// When set, loads Message-ID for this locator (Access Log / list). Otherwise uses Companion Read detail.
    var locator: (accountID: String, placement: String, id: String)? = nil
    /// Use `Open message in Apple Mail` when the focused entity is an attachment (parent handoff).
    var title: String = "Open in Apple Mail"
    /// When false, fail-closed copy is left to the surrounding card (chip-row local note).
    var showsHandoffNote: Bool = true

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            SecondaryActionButton(title: title) {
                if let locator {
                    session.openInMail(
                        accountID: locator.accountID,
                        placement: locator.placement,
                        id: locator.id
                    )
                } else {
                    session.openInMail()
                }
            } icon: {
                OpenInMailGlyph()
            }
            if showsHandoffNote, let handoffNote = session.handoffNote {
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

    var connectedAgentNames: [String] {
        session.agents.pairedAgents.map(\.name)
    }

    var lastAgentKind: AuditKind? {
        session.agents.lastAgentRequest?.kind
    }

    var lastAgentKindLabel: String {
        lastAgentKind?.badgeTitle ?? "—"
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
        guard let clock = lastAgentClock, let relative = lastAgentRelative else { return lastAgentKindLabel }
        return "\(lastAgentKindLabel) \(clock) \(relative)"
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

/// Access-log kind badge plus clock and relative-age chip — same time layout as last ingest.
struct LastAgentCallValue: View {
    let copy: CompanionStatusCopy

    var body: some View {
        HStack(alignment: .center, spacing: 6) {
            if let kind = copy.lastAgentKind {
                AuditKindBadge(kind: kind, compact: true)
                    .fixedSize()
            } else {
                Text("—")
            }
            if let clock = copy.lastAgentClock {
                ClockAndAgeValue(clock: clock, relative: copy.lastAgentRelative)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(copy.lastAgentCall)
    }
}

/// Paired agents as icon glyphs (Access Log / Grant Desk marks).
struct ConnectedAgentsValue: View {
    let names: [String]

    var body: some View {
        Group {
            if names.isEmpty {
                Text("—")
            } else {
                HStack(spacing: 8) {
                    ForEach(Array(names.enumerated()), id: \.offset) { _, name in
                        HStack(spacing: 4) {
                            AgentGlyph(name: name, size: 14)
                            Text(shortName(name))
                                .lineLimit(1)
                        }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel)
    }

    private func shortName(_ name: String) -> String {
        if name.compare("Grok Bot", options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame {
            return "Grok"
        }
        return name
    }

    private var accessibilityLabel: String {
        switch names.count {
        case 0: return "None"
        case 1: return names[0]
        default: return names.joined(separator: ", ")
        }
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
                HStack(alignment: .center, spacing: 8) {
                    Text("Connected agent")
                        .foregroundStyle(.secondary)
                        .frame(width: 118, alignment: .leading)
                    ConnectedAgentsValue(names: copy.connectedAgentNames)
                }
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
}

// MARK: - Access log + grant desk chrome

extension AuditKind {
    var badgeTitle: String {
        switch self {
        case .pair: "pair"
        case .search: "search"
        case .list: "list"
        case .listNew: "new"
        case .listAccounts: "accounts"
        case .get: "get"
        case .getAttachment: "attach"
        case .openInMail: "mail"
        case .proposeSend: "send"
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
        case .listAccounts: "folder"
        case .get: "envelope.open"
        case .getAttachment: "paperclip"
        case .openInMail: "arrow.up.right.square"
        case .proposeSend: "paperplane"
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
    @Environment(\.backgroundProminence) private var backgroundProminence

    private var onProminentBackground: Bool {
        backgroundProminence == .increased
    }

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
        .foregroundStyle(onProminentBackground ? Color.white : Color.accentColor)
        .padding(.horizontal, compact ? 5 : 7)
        .padding(.vertical, compact ? 1 : 3)
        .background(
            (onProminentBackground ? Color.white.opacity(0.22) : Color.accentColor.opacity(0.12)),
            in: Capsule()
        )
        .overlay {
            Capsule().strokeBorder(
                onProminentBackground ? Color.white.opacity(0.75) : Color.accentColor.opacity(0.35),
                lineWidth: 0.5
            )
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

struct MCPMark: View {
    var size: CGFloat = 26

    var body: some View {
        Image("MCPMark")
            .resizable()
            .interpolation(.high)
            .scaledToFit()
            .frame(width: size, height: size)
            .accessibilityLabel("MCP")
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

/// Access Log Request/Response chrome: `[Formatted]` + `JSON` `[Pretty|Raw]`.
/// Picking Pretty/Raw selects JSON — there is no separate JSON button.
enum AccessLogSideView: Equatable {
    case formatted
    case json
}

enum AccessLogJSONStyle: Equatable {
    case pretty
    case raw
}

struct AccessLogModeHeader: View {
    let title: String
    @Binding var view: AccessLogSideView
    @Binding var jsonStyle: AccessLogJSONStyle

    var body: some View {
        HStack(alignment: .center, spacing: 8) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            Spacer(minLength: 8)
            HStack(spacing: 8) {
                AccessLogModeSegmentTrack {
                    AccessLogModeSegmentButton(
                        title: "Formatted",
                        isOn: view == .formatted
                    ) {
                        view = .formatted
                    }
                }

                HStack(spacing: 4) {
                    Text("JSON")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(view == .json ? Color.accentColor : Color.secondary.opacity(0.85))
                    AccessLogModeSegmentTrack {
                        AccessLogModeSegmentButton(
                            title: "Pretty",
                            isOn: view == .json && jsonStyle == .pretty,
                            compact: true
                        ) {
                            jsonStyle = .pretty
                            view = .json
                        }
                        AccessLogModeSegmentButton(
                            title: "Raw",
                            isOn: view == .json && jsonStyle == .raw,
                            compact: true
                        ) {
                            jsonStyle = .raw
                            view = .json
                        }
                    }
                }
                .padding(.horizontal, 4)
                .padding(.vertical, 2)
                .background(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(view == .json ? Color.accentColor.opacity(0.12) : Color.clear)
                )
                .overlay {
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .strokeBorder(
                            view == .json ? Color.accentColor.opacity(0.35) : Color.clear,
                            lineWidth: 1
                        )
                }
            }
        }
        .accessibilityElement(children: .contain)
    }
}

/// Two-segment Access Log chrome: **Formatted** | **Raw** (no JSON Pretty/Raw).
struct FormattedRawModeSegments: View {
    @Binding var showRaw: Bool

    var body: some View {
        AccessLogModeSegmentTrack {
            AccessLogModeSegmentButton(
                title: "Formatted",
                isOn: !showRaw
            ) {
                showRaw = false
            }
            AccessLogModeSegmentButton(
                title: "Raw",
                isOn: showRaw
            ) {
                showRaw = true
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Body preview mode")
    }
}

/// Raised-face track shared by Formatted and JSON Pretty/Raw mode chrome.
struct AccessLogModeSegmentTrack<Content: View>: View {
    @ViewBuilder let content: () -> Content

    var body: some View {
        HStack(spacing: 1) {
            content()
        }
        .padding(1)
        .background {
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor))
                .overlay {
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .strokeBorder(Color.secondary.opacity(0.32), lineWidth: 1)
                }
        }
    }
}

struct AccessLogModeSegmentButton: View {
    let title: String
    let isOn: Bool
    var compact: Bool = false
    let action: () -> Void

    private static let labelFont = Font(
        NSFont.systemFont(ofSize: NSFont.systemFontSize(for: .small))
    )

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(compact ? .system(size: 10, weight: isOn ? .semibold : .regular) : Self.labelFont)
                .fontWeight(isOn ? .semibold : .regular)
                .foregroundStyle(isOn ? Color.primary : Color.secondary)
                .padding(.horizontal, compact ? 8 : 9)
                .padding(.vertical, compact ? 2 : 3)
                .frame(minHeight: SecondaryActionButton.controlHeight - 2)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .background {
            if isOn {
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .fill(Color(nsColor: .controlColor))
                    .shadow(color: Color.black.opacity(0.10), radius: 1, y: 0.5)
            }
        }
        .accessibilityAddTraits(isOn ? .isSelected : [])
        .accessibilityLabel(title)
    }
}

struct GrantFieldChip: View {
    let title: String
    let isOn: Bool
    var systemImage: String? = nil
    var strikethroughWhenOff: Bool = false
    var mode: FieldAccessMode? = nil

    var body: some View {
        HStack(spacing: 4) {
            if let systemImage {
                Image(systemName: systemImage)
                    .font(.caption2)
            }
            Text(title)
                .font(.caption)
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
            if let mode, mode == .ask {
                Text("?")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(askColor)
            }
        }
        .foregroundStyle(foregroundColor)
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(
            Capsule()
                .fill(backgroundColor)
        )
        .overlay(
            Capsule()
                .strokeBorder(
                    borderColor,
                    lineWidth: borderWidth
                )
        )
        .strikethrough(strikethroughWhenOff && !isOn, color: Color.secondary.opacity(0.45))
        .fixedSize(horizontal: true, vertical: false)
    }
    
    private var foregroundColor: Color {
        if let mode {
            switch mode {
            case .on: return Color.accentColor
            case .ask: return askColor
            case .off: return Color.secondary
            }
        }
        return isOn ? Color.accentColor : Color.secondary
    }
    
    private var backgroundColor: Color {
        if let mode {
            switch mode {
            case .on: return Color.accentColor.opacity(0.12)
            case .ask: return askColor.opacity(0.12)
            case .off: return Color.secondary.opacity(0.08)
            }
        }
        return isOn ? Color.accentColor.opacity(0.12) : Color.secondary.opacity(0.08)
    }
    
    private var borderColor: Color {
        if let mode {
            switch mode {
            case .on: return Color.accentColor.opacity(0.45)
            case .ask: return askColor.opacity(0.45)
            case .off: return Color.secondary.opacity(0.25)
            }
        }
        return isOn ? Color.accentColor.opacity(0.45) : Color.secondary.opacity(0.25)
    }
    
    private var borderWidth: CGFloat {
        if let mode {
            return mode == .off ? 0.5 : 1.5
        }
        return isOn ? 1.5 : 0.5
    }
    
    private var askColor: Color {
        Color.orange
    }
}

/// Horizontal chip row that wraps to extra lines instead of compressing children.
struct GrantChipFlow: Layout {
    var spacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        arrange(proposal: proposal, subviews: subviews).size
    }

    func placeSubviews(
        in bounds: CGRect,
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout ()
    ) {
        let frames = arrange(proposal: proposal, subviews: subviews).frames
        for index in subviews.indices {
            subviews[index].place(
                at: CGPoint(
                    x: bounds.minX + frames[index].minX,
                    y: bounds.minY + frames[index].minY
                ),
                proposal: ProposedViewSize(frames[index].size)
            )
        }
    }

    private func arrange(
        proposal: ProposedViewSize,
        subviews: Subviews
    ) -> (size: CGSize, frames: [CGRect]) {
        let maxWidth = proposal.width ?? .infinity
        var frames: [CGRect] = []
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0
        var usedWidth: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > 0, x + size.width > maxWidth {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            frames.append(CGRect(origin: CGPoint(x: x, y: y), size: size))
            rowHeight = max(rowHeight, size.height)
            x += size.width + spacing
            usedWidth = max(usedWidth, x - spacing)
        }

        return (
            CGSize(width: usedWidth, height: y + rowHeight),
            frames
        )
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

    private enum Tint {
        case pass
        case block
        case conditionalAllowed
        case conditionalBlocked
        case granted
        case ask
        case off
    }

    let fields: GrantFields
    var interactive: Bool = false
    /// When false, omit greyed-out (disabled) field chips.
    var showOff: Bool = true
    var labelMode: LabelMode = .letter
    /// Fields newly revealed by an effectful Pass (Access Log tint).
    var passRevealed: GrantFields = .none
    /// Fields newly withheld by an effectful Block (Access Log tint).
    var blockWithheld: GrantFields = .none
    /// Fields the user Allowed on an Ask prompt for this get (Access Log tint).
    var conditionalConfirmed: GrantFields = .none
    /// Fields the user Blocked on an Ask prompt for this get (Access Log tint).
    var conditionalBlocked: GrantFields = .none
    /// Subset of Ask allow/block that came from Remember Ask (no popup on this get).
    var conditionalRemembered: GrantFields = .none
    var onToggle: ((WritableKeyPath<GrantFields, FieldAccessMode>) -> Void)? = nil

    private struct Item: Identifiable {
        let id: String
        let letter: String
        let short: String
        let title: String
        let systemImage: String
        let keyPath: WritableKeyPath<GrantFields, Bool>
        let modeKeyPath: WritableKeyPath<GrantFields, FieldAccessMode>
    }

    private static let items: [Item] = [
        Item(id: "subject", letter: "S", short: "Subj", title: "Subject", systemImage: "text.alignleft", keyPath: \.subject, modeKeyPath: \.subjectMode),
        Item(id: "from", letter: "F", short: "From", title: "From", systemImage: "envelope", keyPath: \.from, modeKeyPath: \.fromMode),
        Item(id: "to", letter: "T", short: "To", title: "To", systemImage: "tray.and.arrow.down", keyPath: \.to, modeKeyPath: \.toMode),
        Item(id: "cc", letter: "Cc", short: "Cc", title: "Cc", systemImage: "person.2", keyPath: \.cc, modeKeyPath: \.ccMode),
        Item(id: "date", letter: "D", short: "Date", title: "Date & Time", systemImage: "calendar", keyPath: \.date, modeKeyPath: \.dateMode),
        Item(id: "body", letter: "B", short: "Body", title: "Body", systemImage: "doc.plaintext", keyPath: \.body, modeKeyPath: \.bodyMode),
        Item(id: "att", letter: "A", short: "Att", title: "Attachment names", systemImage: "paperclip", keyPath: \.attachmentMetadata, modeKeyPath: \.attachmentMetadataMode),
        Item(id: "bytes", letter: "C", short: "File", title: "Attachment content", systemImage: "doc", keyPath: \.attachmentContent, modeKeyPath: \.attachmentContentMode),
    ]

    private var askColor: Color { Color.orange }

    var body: some View {
        HStack(spacing: 2) {
            ForEach(Self.items) { item in
                let mode = fields[keyPath: item.modeKeyPath]
                let tint = tint(for: item, mode: mode)
                if showOff || mode != .off || tint == .pass || tint == .block
                    || tint == .conditionalAllowed || tint == .conditionalBlocked
                {
                    if interactive, let onToggle {
                        Button {
                            onToggle(item.modeKeyPath)
                        } label: {
                            compactBadge(item, mode: mode, tint: tint)
                        }
                        .buttonStyle(.plain)
                        .help(helpText(item, tint: tint))
                        .accessibilityLabel(accessibilityLabel(item, tint: tint))
                    } else {
                        compactBadge(item, mode: mode, tint: tint)
                            .help(helpText(item, tint: tint))
                            .accessibilityLabel(accessibilityLabel(item, tint: tint))
                    }
                }
            }
        }
        .fixedSize(horizontal: true, vertical: false)
    }

    private func tint(for item: Item, mode: FieldAccessMode) -> Tint {
        if blockWithheld[keyPath: item.keyPath] { return .block }
        if passRevealed[keyPath: item.keyPath] { return .pass }
        if conditionalBlocked[keyPath: item.keyPath] { return .conditionalBlocked }
        if conditionalConfirmed[keyPath: item.keyPath] { return .conditionalAllowed }
        switch mode {
        case .on: return .granted
        case .ask: return .ask
        case .off: return .off
        }
    }

    private func compactBadge(_ item: Item, mode: FieldAccessMode, tint: Tint) -> some View {
        let ink = ink(for: tint)
        let weight: Font.Weight =
            (tint == .pass || tint == .block
                || tint == .conditionalAllowed || tint == .conditionalBlocked
                || mode != .off)
            ? .medium : .regular
        let sidePad: CGFloat = labelMode == .icon ? 5 : 4
        let showsAskMark = tint == .conditionalAllowed || tint == .conditionalBlocked
        let showsRememberedAsk = showsAskMark && conditionalRemembered[keyPath: item.keyPath]
        return HStack(spacing: 2) {
            Image(systemName: item.systemImage)
                .font(.system(size: 8, weight: weight))
            if let text = labelText(item) {
                Text(text)
                    .font(.system(size: 8, weight: weight))
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)
                    .strikethrough(mode == .off, color: ink.opacity(tint == .off ? 0.45 : 0.55))
            }
            if showsAskMark {
                if showsRememberedAsk {
                    Image(systemName: "clock.arrow.circlepath")
                        .font(.system(size: 8, weight: .semibold))
                        .symbolRenderingMode(.monochrome)
                        .offset(y: -0.5)
                } else {
                    Image(systemName: "questionmark.circle.fill")
                        .font(.system(size: 9, weight: .semibold))
                        .symbolRenderingMode(.monochrome)
                        .offset(y: -0.5)
                }
            }
        }
        .foregroundStyle(ink)
        .padding(.leading, sidePad)
        // Live Ask mark sits tight (1); clock glyph needs a bit more trailing room.
        .padding(.trailing, showsAskMark ? (showsRememberedAsk ? 3 : 2) : sidePad)
        .frame(height: 14)
        .background(
            Capsule()
                .fill(fill(for: tint))
        )
        .overlay(
            Capsule()
                .strokeBorder(stroke(for: tint), lineWidth: 0.5)
        )
        .fixedSize(horizontal: true, vertical: false)
    }

    private func ink(for tint: Tint) -> Color {
        switch tint {
        case .pass, .conditionalAllowed: RuleMarkStyle.passGreen
        case .block, .conditionalBlocked: RuleMarkStyle.blockRed
        case .ask: askColor
        case .granted: Color.accentColor
        case .off: Color.secondary.opacity(0.55)
        }
    }

    private func fill(for tint: Tint) -> Color {
        switch tint {
        case .pass, .conditionalAllowed: RuleMarkStyle.passGreen.opacity(0.12)
        case .block, .conditionalBlocked: RuleMarkStyle.blockRed.opacity(0.12)
        case .ask: askColor.opacity(0.12)
        case .granted: Color.accentColor.opacity(0.12)
        case .off: Color.secondary.opacity(0.08)
        }
    }

    private func stroke(for tint: Tint) -> Color {
        switch tint {
        case .pass, .conditionalAllowed: RuleMarkStyle.passBorder
        case .block, .conditionalBlocked: RuleMarkStyle.blockBorder
        case .ask: askColor.opacity(0.45)
        case .granted: Color.accentColor.opacity(0.35)
        case .off: Color.secondary.opacity(0.2)
        }
    }

    private func helpText(_ item: Item, tint: Tint) -> String {
        let remembered = conditionalRemembered[keyPath: item.keyPath]
        switch tint {
        case .pass: return "\(item.title) — revealed by Pass"
        case .block: return "\(item.title) — withheld by Block"
        case .conditionalAllowed:
            return remembered
                ? "\(item.title) — user allowed (cached)"
                : "\(item.title) — user allowed after Ask"
        case .conditionalBlocked:
            return remembered
                ? "\(item.title) — user blocked (cached)"
                : "\(item.title) — user blocked after Ask"
        case .granted: return "\(item.title) — On"
        case .ask: return "\(item.title) — Ask"
        case .off: return "\(item.title) — Off"
        }
    }

    private func accessibilityLabel(_ item: Item, tint: Tint) -> String {
        helpText(item, tint: tint)
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

enum FileCardStyle {
    static let missingStripe = Color(red: 0.60, green: 0.64, blue: 0.70).opacity(0.55)
    static let missingFill = Color(red: 0.93, green: 0.95, blue: 0.97)
    static let hugeStripe = Color.orange.opacity(0.35)
    static let hugeFill = Color.orange.opacity(0.08)
    static let hugeInk = Color.orange
}

/// Delivered attachment result (`get_attachment`) — see `docs/ui-inventory.md` → FileCard.
struct FileCard: View {
    let model: AccessLogFormat.AttachmentCardModel
    var showsPreview: Bool = true
    /// Attach Formatted shows the locked legend under denied cards; get nested content does not.
    var showsLockedLegend: Bool = true
    /// Nested `get` Formatted suppresses per-card copy; one note sits under the list instead.
    var showsPreviewBlockedReason: Bool = true
    var onPreview: (() -> Void)? = nil

    /// Match Attachment Info `attachmentTile` radius when side-by-side in get Formatted.
    private static let cardRadius: CGFloat = 6

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            cardChrome
            if showsLockedLegend, model.state == .denied {
                LockedFieldsLegend()
            }
            if showsPreview, showsPreviewBlockedReason, let reason = model.previewBlockedReason {
                Text(reason)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if let note = model.note, !note.isEmpty {
                Text(note)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if model.isPartial {
                Text(partialCaption)
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
        }
    }

    @ViewBuilder
    private var cardChrome: some View {
        Group {
            if model.state == .granted {
                grantedRow
            } else {
                blockedStack
            }
        }
        .padding(8)
        .background { cardBackground }
        .overlay { cardBorder }
        .clipShape(RoundedRectangle(cornerRadius: Self.cardRadius, style: .continuous))
    }

    private var grantedRow: some View {
        HStack(alignment: .center, spacing: 10) {
            leadingGlyph
            VStack(alignment: .leading, spacing: 2) {
                filenameLabel
                subLine
                if let passNick = model.passNick {
                    RuleFieldMarkChip(nick: passNick, polarity: .pass)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            previewControl
        }
    }

    /// Non-granted: compact glyph + name on one row; state copy spans the full card width.
    private var blockedStack: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .center, spacing: 8) {
                leadingGlyph
                filenameLabel
                    .frame(maxWidth: .infinity, alignment: .leading)
                previewControl
            }
            Text(model.stateLine)
                .font(.caption.italic())
                .foregroundStyle(stateCopyColor)
                .frame(maxWidth: .infinity, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
            if let passNick = model.passNick {
                RuleFieldMarkChip(nick: passNick, polarity: .pass)
            }
        }
    }

    private var filenameLabel: some View {
        Text(model.filename)
            .font(.caption.weight(.semibold))
            .lineLimit(1)
            .truncationMode(.middle)
            .foregroundStyle(model.state == .granted ? Color.primary : Color.secondary)
    }

    @ViewBuilder
    private var previewControl: some View {
        if showsPreview {
            SecondaryActionButton(title: "Preview", systemImage: "eye") {
                onPreview?()
            }
        }
    }

    private var partialCaption: String {
        switch model.state {
        case .granted:
            return "Mail marks this message as a partial download. This file was still delivered."
        case .missing:
            return "Mail marks this message as a partial download — attachment bytes may not be on disk."
        default:
            return "Mail marks this message as a partial download."
        }
    }

    @ViewBuilder
    private var subLine: some View {
        HStack(spacing: 6) {
            Text(model.typeDescription)
                .foregroundStyle(.secondary)
            if let size = model.sizeLabel {
                Text("·").foregroundStyle(.tertiary)
                Text(size)
                    .foregroundStyle(.secondary)
            }
        }
        .font(.caption)
    }

    private var stateCopyColor: Color {
        switch model.state {
        case .granted: .secondary
        case .denied: HatchDeniedStyle.legend
        case .missing: Color(red: 0.37, green: 0.43, blue: 0.53)
        case .huge: FileCardStyle.hugeInk
        }
    }

    @ViewBuilder
    private var leadingGlyph: some View {
        switch model.state {
        case .granted:
            ZStack {
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [
                                Color(red: 0.97, green: 0.97, blue: 0.98),
                                Color(red: 0.91, green: 0.92, blue: 0.95)
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                Text(model.typeBadge)
                    .font(.system(size: 9, weight: .bold).monospaced())
                    .foregroundStyle(HatchDeniedStyle.legend)
                    .minimumScaleFactor(0.7)
                    .lineLimit(1)
                // Dog-ear (top-trailing) — drawn after the label so it does not steal layout.
                VStack(spacing: 0) {
                    HStack(spacing: 0) {
                        Spacer(minLength: 0)
                        Path { path in
                            path.move(to: CGPoint(x: 0, y: 0))
                            path.addLine(to: CGPoint(x: 8, y: 0))
                            path.addLine(to: CGPoint(x: 8, y: 8))
                            path.closeSubpath()
                        }
                        .fill(Color(nsColor: .textBackgroundColor))
                        .frame(width: 8, height: 8)
                        .overlay(alignment: .bottomLeading) {
                            Path { path in
                                path.move(to: CGPoint(x: 0, y: 0))
                                path.addLine(to: CGPoint(x: 8, y: 8))
                            }
                            .stroke(Color(red: 0.79, green: 0.82, blue: 0.87), lineWidth: 1)
                        }
                    }
                    Spacer(minLength: 0)
                }
            }
            .frame(width: 28, height: 34)
            .overlay {
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .strokeBorder(Color(red: 0.79, green: 0.82, blue: 0.87), lineWidth: 1)
            }
            .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
        case .denied:
            statusIcon {
                HatchLockIcon()
            }
            .foregroundStyle(HatchDeniedStyle.legend)
            .overlay {
                RoundedRectangle(cornerRadius: SecondaryActionMetrics.cornerRadius, style: .continuous)
                    .strokeBorder(HatchDeniedStyle.stripe, lineWidth: 1)
            }
        case .missing:
            statusIcon {
                Text("✕")
                    .font(.system(size: 10, weight: .heavy))
            }
            .foregroundStyle(Color(red: 0.37, green: 0.43, blue: 0.53))
            .overlay {
                RoundedRectangle(cornerRadius: SecondaryActionMetrics.cornerRadius, style: .continuous)
                    .strokeBorder(FileCardStyle.missingStripe, lineWidth: 1)
            }
        case .huge:
            statusIcon {
                Text("!")
                    .font(.system(size: 10, weight: .heavy))
            }
            .foregroundStyle(FileCardStyle.hugeInk)
            .overlay {
                RoundedRectangle(cornerRadius: SecondaryActionMetrics.cornerRadius, style: .continuous)
                    .strokeBorder(Color.orange.opacity(0.45), lineWidth: 1)
            }
        }
    }

    /// Match trailing Preview / chip-row `SecondaryAction` (20×20 / radius 6).
    private func statusIcon<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        let side = SecondaryActionMetrics.controlHeight
        return content()
            .frame(width: side, height: side)
            .background(
                Color(nsColor: .controlBackgroundColor),
                in: RoundedRectangle(cornerRadius: SecondaryActionMetrics.cornerRadius, style: .continuous)
            )
    }

    @ViewBuilder
    private var cardBackground: some View {
        switch model.state {
        case .granted:
            Color(nsColor: .textBackgroundColor)
        case .denied:
            HatchPattern()
        case .missing:
            Canvas { context, size in
                let spacing: CGFloat = 6
                var path = Path()
                let extent = size.width + size.height
                var x: CGFloat = -size.height
                while x < extent {
                    path.move(to: CGPoint(x: x, y: 0))
                    path.addLine(to: CGPoint(x: x + size.height, y: size.height))
                    x += spacing
                }
                context.stroke(path, with: .color(FileCardStyle.missingStripe.opacity(0.35)), lineWidth: 1)
                context.fill(Path(CGRect(origin: .zero, size: size)), with: .color(FileCardStyle.missingFill))
            }
        case .huge:
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
                context.stroke(path, with: .color(FileCardStyle.hugeStripe), lineWidth: 1)
                context.fill(Path(CGRect(origin: .zero, size: size)), with: .color(FileCardStyle.hugeFill))
            }
        }
    }

    @ViewBuilder
    private var cardBorder: some View {
        let shape = RoundedRectangle(cornerRadius: Self.cardRadius, style: .continuous)
        switch model.state {
        case .granted:
            shape.strokeBorder(Color.secondary.opacity(0.2), lineWidth: 1)
        case .denied:
            shape.strokeBorder(HatchDeniedStyle.stripe, style: StrokeStyle(lineWidth: 1.5, dash: [4, 3]))
        case .missing:
            shape.strokeBorder(FileCardStyle.missingStripe, style: StrokeStyle(lineWidth: 1.5, dash: [4, 3]))
        case .huge:
            shape.strokeBorder(Color.orange.opacity(0.45), style: StrokeStyle(lineWidth: 1.5, dash: [4, 3]))
        }
    }
}

/// One search/list hit as returned to the agent — see `docs/ui-inventory.md` → SearchResultCard.
struct SearchResultCard: View {
    let session: CompanionSession
    let ref: AuditMessageRef

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .center, spacing: 8) {
                HStack(spacing: 6) {
                    Text(ref.placement)
                        .font(.caption)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(.quaternary, in: RoundedRectangle(cornerRadius: 4))
                    if ref.isPartial {
                        PartialBadge()
                    }
                }
                Spacer(minLength: 8)
                HStack(spacing: 6) {
                    SecondaryActionButton(title: "Preview", systemImage: "eye") {
                        session.openRead(
                            accountID: ref.accountID,
                            placement: ref.placement,
                            id: ref.id
                        )
                        DetachedWindowHost.shared.showCompanion(session: session)
                    }
                    OpenInMailButton(
                        session: session,
                        locator: (ref.accountID, ref.placement, ref.id)
                    )
                }
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(ref.fields.subject
                     ? (ref.subject.isEmpty ? "(no subject)" : ref.subject)
                     : ref.id)
                    .font(.caption.weight(.semibold))
                    .frame(maxWidth: .infinity, alignment: .leading)
                labeled("From", ref.fields.from ? ref.from : "")
                labeled("Date", AccessLogFormat.compactMailDate(ref.date) ?? ref.date)
                labeled("Id", ref.id, mono: true)
                labeled("Account", session.accountLabel(ref.accountID))
            }
        }
        .padding(10)
        .overlay {
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(Color.secondary.opacity(0.2), lineWidth: 1)
        }
    }

    private func labeled(_ label: String, _ value: String, mono: Bool = false) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text("\(label):")
                .fontWeight(.light)
                .foregroundStyle(.secondary)
            Text(value.isEmpty ? " " : value)
                .font(mono ? .caption.monospaced() : .caption)
                .foregroundStyle(value.isEmpty ? .secondary : .primary)
                .textSelection(.enabled)
        }
        .font(.caption)
    }
}

struct MessageAccessCard: View {
    let session: CompanionSession
    let ref: AuditMessageRef
    var omitsBody: Bool = false
    var showsFieldBadges: Bool = true
    var attachmentContentDetail: String = "none in this response"
    /// When set, Attachment Content uses FileCard chrome.
    var attachmentContentCards: [AccessLogFormat.AttachmentCardModel]? = nil
    /// Access Log get: per-file Preview on Attachment Content cards (opens bytes from Mail).
    var onAttachmentPreview: ((String) -> Void)? = nil
    /// Access Log get: Source chip left · Preview + Open in Apple Mail right.
    var showsChipRowActions: Bool = false
    var chipRowPreviewEnabled: Bool = true
    var chipRowPreviewBlockedReason: String? = nil
    var onChipRowPreview: (() -> Void)? = nil
    var mailHandoffTitle: String = "Open in Apple Mail"
    /// Pass nick when a field is visible only via a matching Pass (Access preview).
    var bodyViaPassNick: String? = nil
    var attachmentInfoViaPassNick: String? = nil
    var attachmentContentViaPassNick: String? = nil
    /// Access Log: currently open leak detections panel scope (drives field-badge expanded chrome).
    var leakPanelScope: AccessLogLeakPanelScope? = nil
    /// Access Log: toggle detections panel filtered to Subject / Body.
    var onToggleLeakPanel: ((AccessLogLeakPanelScope) -> Void)? = nil

    @State private var chipRowNote: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if showsChipRowActions {
                chipRow
            } else {
                SourceChip(session: session, accountID: ref.accountID, placement: ref.placement)
            }
            cardFields
            if let chipRowNote {
                Text(chipRowNote)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(10)
        .overlay {
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(Color.secondary.opacity(0.2), lineWidth: 1)
        }
    }

    @ViewBuilder
    private var cardFields: some View {
        VStack(alignment: .leading, spacing: 8) {
            if showsFieldBadges {
                GrantFieldBadgeRow(
                    fields: ref.fields,
                    passRevealed: ref.passRevealedFields,
                    blockWithheld: ref.blockWithheldFields,
                    conditionalConfirmed: ref.conditionalConfirmedFields,
                    conditionalBlocked: ref.conditionalUserBlockedFields,
                    conditionalRemembered: ref.conditionalRememberedFields
                )
            }
            subjectPreview
            if ref.fields.from {
                AddressLine(label: "From", raw: ref.from) {
                    fieldMarks(for: \.from)
                }
            } else {
                previewRow(
                    "From",
                    ref.from,
                    false,
                    mark: ruleMark(for: \.from),
                    conditional: conditionalAskMark(for: \.from)
                )
            }
            if ref.fields.to {
                AddressLine(label: "To", raw: ref.to) {
                    fieldMarks(for: \.to)
                }
            } else {
                previewRow(
                    "To",
                    ref.to,
                    false,
                    mark: ruleMark(for: \.to),
                    conditional: conditionalAskMark(for: \.to)
                )
            }
            if ref.fields.cc {
                AddressLine(label: "Cc", raw: ref.cc) {
                    fieldMarks(for: \.cc)
                }
            } else {
                previewRow(
                    "Cc",
                    ref.cc,
                    false,
                    mark: ruleMark(for: \.cc),
                    conditional: conditionalAskMark(for: \.cc)
                )
            }
            previewRow(
                "Date & Time",
                AccessLogFormat.compactMailDate(ref.date) ?? ref.date,
                ref.fields.date,
                mark: ruleMark(for: \.date),
                conditional: conditionalAskMark(for: \.date)
            )
            Divider()
            labeledSection(
                "Body",
                mark: bodyRuleMark,
                conditional: conditionalAskMark(for: \.body),
                leakCount: leakHitCount(for: .body),
                leakScope: .body
            ) {
                bodyPreview
            }
            Divider()
            HStack(alignment: .top, spacing: 6) {
                attachmentColumn(
                    "Attachment Info",
                    granted: ref.fields.attachmentMetadata,
                    mark: attachmentInfoRuleMark,
                    conditional: conditionalAskMark(for: \.attachmentMetadata)
                ) {
                    if ref.attachments.isEmpty {
                        attachmentTile(detail: "none in this response")
                    } else {
                        ForEach(Array(ref.attachments.enumerated()), id: \.offset) { _, attachment in
                            attachmentTile(detail: "\(attachment.filename) · \(attachment.sizeLabel)")
                        }
                    }
                }
                attachmentColumn(
                    "Attachment Content",
                    granted: attachmentContentCards != nil || ref.fields.attachmentContent,
                    mark: attachmentContentRuleMark,
                    conditional: conditionalAskMark(for: \.attachmentContent)
                ) {
                    if let cards = attachmentContentCards, !cards.isEmpty {
                        VStack(alignment: .leading, spacing: 6) {
                            ForEach(Array(cards.enumerated()), id: \.offset) { _, card in
                                let previewName = Self.previewableAttachmentFilename(card.filename)
                                FileCard(
                                    model: card,
                                    showsPreview: previewName != nil && onAttachmentPreview != nil,
                                    showsLockedLegend: false,
                                    showsPreviewBlockedReason: false
                                ) {
                                    if let previewName {
                                        onAttachmentPreview?(previewName)
                                    }
                                }
                            }
                            if AccessLogFormat.showsGetAttachmentContentPreviewNote(for: cards) {
                                Text(AccessLogFormat.getAttachmentContentPreviewNote)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                    } else {
                        attachmentTile(detail: attachmentContentDetail)
                    }
                }
            }
        }
    }

    private var chipRow: some View {
        HStack(alignment: .center, spacing: 8) {
            SourceChip(session: session, accountID: ref.accountID, placement: ref.placement)
            Spacer(minLength: 8)
            HStack(spacing: 6) {
                SecondaryActionButton(title: "Preview", systemImage: "eye") {
                    if chipRowPreviewEnabled {
                        chipRowNote = nil
                        onChipRowPreview?()
                    } else {
                        chipRowNote = chipRowPreviewBlockedReason
                            ?? "Not available from this agent response"
                    }
                }
                OpenInMailButton(
                    session: session,
                    locator: (ref.accountID, ref.placement, ref.id),
                    title: mailHandoffTitle,
                    showsHandoffNote: false
                )
            }
        }
    }

    private var bodyRuleMark: AppliedGrantRule? {
        if let nick = bodyViaPassNick {
            return AppliedGrantRule(id: "preview", nick: nick, polarity: .pass)
        }
        return ruleMark(for: \.body)
    }

    private var attachmentInfoRuleMark: AppliedGrantRule? {
        if let nick = attachmentInfoViaPassNick {
            return AppliedGrantRule(id: "preview", nick: nick, polarity: .pass)
        }
        return ruleMark(for: \.attachmentMetadata)
    }

    private var attachmentContentRuleMark: AppliedGrantRule? {
        if let nick = attachmentContentViaPassNick {
            return AppliedGrantRule(id: "preview", nick: nick, polarity: .pass)
        }
        return ruleMark(for: \.attachmentContent)
    }

    /// Placeholders from `getAttachmentContentCards` when nothing was named — no file to open.
    private static func previewableAttachmentFilename(_ filename: String) -> String? {
        switch filename {
        case "(attachment)", "(none named)": return nil
        default: return filename
        }
    }

    private func ruleMark(for keyPath: KeyPath<GrantFields, Bool>) -> AppliedGrantRule? {
        ref.appliedRuleMark(for: keyPath)
    }

    private func conditionalAskMark(for keyPath: KeyPath<GrantFields, Bool>) -> ConditionalAskMark? {
        let remembered = ref.conditionalRememberedFields[keyPath: keyPath]
        if ref.conditionalUserBlockedFields[keyPath: keyPath] {
            return ConditionalAskMark(outcome: .blocked, remembered: remembered)
        }
        if ref.conditionalConfirmedFields[keyPath: keyPath] {
            return ConditionalAskMark(outcome: .allowed, remembered: remembered)
        }
        return nil
    }

    @ViewBuilder
    private func fieldMarks(for keyPath: KeyPath<GrantFields, Bool>) -> some View {
        HStack(spacing: 4) {
            if let mark = conditionalAskMark(for: keyPath) {
                ConditionalFieldMarkChip(outcome: mark.outcome, remembered: mark.remembered)
            }
            if let mark = ruleMark(for: keyPath) {
                RuleFieldMarkChip(nick: mark.nick, polarity: mark.polarity)
            }
        }
    }

    private func leakHitCount(for field: AuditLeakDetection.Field) -> Int {
        ref.displayLeakDetections.filter { $0.field == field }.count
    }

    @ViewBuilder
    private var subjectPreview: some View {
        leakGuardRow(
            label: "Subject",
            text: ref.subject.isEmpty ? "(no subject)" : ref.subject,
            fieldGranted: ref.fields.subject,
            access: effectiveSubjectAccess,
            original: ref.subjectOriginal,
            deniedPlaceholder: ref.subject.isEmpty ? "(no subject)" : ref.subject,
            mark: ruleMark(for: \.subject),
            conditional: conditionalAskMark(for: \.subject),
            leakCount: leakHitCount(for: .subject),
            leakScope: .subject
        )
    }

    @ViewBuilder
    private var bodyPreview: some View {
        if omitsBody, effectiveBodyAccess != .notGranted {
            omittedBodyPreview
        } else if effectiveBodyAccess == .notGranted {
            HatchDeniedLabel(
                placeholder: "Body / snippet",
                fixedHeight: 112,
                helpText: hatchHelp(for: conditionalAskMark(for: \.body))
            )
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
            HatchDeniedLabel(
                placeholder: "Body / snippet",
                helpText: hatchHelp(for: conditionalAskMark(for: \.body))
            )
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
        deniedPlaceholder: String,
        mark: AppliedGrantRule? = nil,
        conditional: ConditionalAskMark? = nil,
        leakCount: Int = 0,
        leakScope: AccessLogLeakPanelScope? = nil
    ) -> some View {
        HStack(alignment: .top, spacing: 6) {
            Text("\(label):")
                .fontWeight(.light)
                .foregroundStyle(.secondary)
            if !fieldGranted {
                HatchDeniedLabel(
                    placeholder: deniedPlaceholder,
                    helpText: hatchHelp(for: conditional)
                )
            } else {
                switch access {
                case .granted, .notAvailable:
                    Text(text)
                        .foregroundStyle(text.hasPrefix("(") ? .secondary : .primary)
                        .textSelection(.enabled)
                case .notGranted:
                    HatchDeniedLabel(
                        placeholder: deniedPlaceholder,
                        helpText: hatchHelp(for: conditional)
                    )
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
            if let conditional {
                ConditionalFieldMarkChip(outcome: conditional.outcome, remembered: conditional.remembered)
            }
            fieldLeakBadge(count: leakCount, scope: leakScope)
            if let mark {
                RuleFieldMarkChip(nick: mark.nick, polarity: mark.polarity)
            }
        }
        .font(.caption)
    }

    @ViewBuilder
    private func fieldLeakBadge(count: Int, scope: AccessLogLeakPanelScope?) -> some View {
        if count > 0, let scope, let onToggleLeakPanel {
            AccessLogLeakHitBadge(
                count: count,
                compact: true,
                action: { onToggleLeakPanel(scope) },
                expanded: leakPanelScope == scope
            )
        }
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

    private func labeledSection<Content: View>(
        _ title: String,
        mark: AppliedGrantRule?,
        conditional: ConditionalAskMark? = nil,
        leakCount: Int = 0,
        leakScope: AccessLogLeakPanelScope? = nil,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            sectionTitle(
                title,
                mark: mark,
                conditional: conditional,
                leakCount: leakCount,
                leakScope: leakScope
            )
            content()
        }
    }

    private func sectionTitle(
        _ title: String,
        mark: AppliedGrantRule?,
        conditional: ConditionalAskMark? = nil,
        leakCount: Int = 0,
        leakScope: AccessLogLeakPanelScope? = nil
    ) -> some View {
        HStack(alignment: .center, spacing: 6) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer(minLength: 4)
            if let conditional {
                ConditionalFieldMarkChip(outcome: conditional.outcome, remembered: conditional.remembered)
            }
            fieldLeakBadge(count: leakCount, scope: leakScope)
            if let mark {
                RuleFieldMarkChip(nick: mark.nick, polarity: mark.polarity)
            }
        }
    }

    @ViewBuilder
    private func previewRow(
        _ label: String,
        _ value: String,
        _ granted: Bool,
        empty: String = " ",
        mark: AppliedGrantRule? = nil,
        conditional: ConditionalAskMark? = nil
    ) -> some View {
        HStack(alignment: .top, spacing: 6) {
            Text("\(label):")
                .fontWeight(.light)
                .foregroundStyle(.secondary)
            if granted {
                Text(value.isEmpty ? empty : value)
                    .foregroundStyle(value.isEmpty ? .secondary : .primary)
                    .textSelection(.enabled)
            } else {
                HatchDeniedLabel(
                    placeholder: value.isEmpty ? empty : value,
                    helpText: hatchHelp(for: conditional)
                )
            }
            if let conditional {
                ConditionalFieldMarkChip(outcome: conditional.outcome, remembered: conditional.remembered)
            }
            if let mark {
                RuleFieldMarkChip(nick: mark.nick, polarity: mark.polarity)
            }
        }
        .font(.caption)
    }

    private func hatchHelp(for conditional: ConditionalAskMark?) -> String? {
        conditional?.outcome == .blocked ? "Locked — user blocked after Ask" : nil
    }

    private func attachmentColumn<Content: View>(
        _ title: String,
        granted: Bool,
        mark: AppliedGrantRule? = nil,
        conditional: ConditionalAskMark? = nil,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            sectionTitle(title, mark: mark, conditional: conditional)
            if granted {
                content()
            } else {
                attachmentTile(
                    detail: nil,
                    helpText: hatchHelp(for: conditional)
                )
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func attachmentTile(detail: String?, helpText: String? = nil) -> some View {
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
                    HatchDeniedLabel(fixedHeight: 18, helpText: helpText)
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

/// Shared Pass / Block mark colors (Access tab badges, Rules nick chips, Access Log).
enum RuleMarkStyle {
    static let passGreen = Color(red: 36 / 255, green: 138 / 255, blue: 61 / 255)
    static let passBorder = Color(red: 143 / 255, green: 209 / 255, blue: 160 / 255)
    static let blockRed = Color(red: 215 / 255, green: 0 / 255, blue: 21 / 255)
    static let blockBorder = Color(red: 240 / 255, green: 180 / 255, blue: 187 / 255)
    /// Filled-circle marks in Access Log list rows and field chips (Ask / Pass / Block).
    static let circleFillIconSize: CGFloat = 12
}

/// Compact mark for a field revealed by Pass or withheld by Block (Access preview / Access Log).
struct RuleFieldMarkChip: View {
    let nick: String
    var polarity: RulePolarity = .pass

    var body: some View {
        HStack(spacing: 2) {
            Image(systemName: polarity == .pass ? "checkmark.circle.fill" : "xmark.circle.fill")
                .font(.system(size: RuleMarkStyle.circleFillIconSize, weight: .semibold))
                .symbolRenderingMode(.monochrome)
            Text(nick)
                .font(.caption.weight(.bold))
        }
        .foregroundStyle(polarity == .pass ? RuleMarkStyle.passGreen : RuleMarkStyle.blockRed)
        .accessibilityLabel(
            polarity == .pass ? "Via pass \(nick)" : "Withheld by block \(nick)"
        )
    }
}

/// Outcome of an Ask (conditional) prompt for one field on a get.
enum ConditionalFieldOutcome {
    case allowed
    case blocked

    var label: String {
        switch self {
        case .allowed: "user allowed"
        case .blocked: "user blocked"
        }
    }

    func label(remembered: Bool) -> String {
        remembered ? "\(label) (cached)" : label
    }

    var helpText: String {
        switch self {
        case .allowed: "User allowed after Ask"
        case .blocked: "User blocked after Ask"
        }
    }

    func helpText(remembered: Bool) -> String {
        switch (self, remembered) {
        case (.allowed, true): "User allowed (cached)"
        case (.blocked, true): "User blocked (cached)"
        case (.allowed, false): "User allowed after Ask"
        case (.blocked, false): "User blocked after Ask"
        }
    }

    var color: Color {
        switch self {
        case .allowed: RuleMarkStyle.passGreen
        case .blocked: RuleMarkStyle.blockRed
        }
    }
}

/// Ask outcome plus whether it came from Remember Ask reuse.
struct ConditionalAskMark: Equatable {
    var outcome: ConditionalFieldOutcome
    var remembered: Bool = false
}

/// Compact mark for a field decided on an Ask (conditional) prompt.
struct ConditionalFieldMarkChip: View {
    var outcome: ConditionalFieldOutcome = .allowed
    /// True when the decision came from Remember Ask (no popup on this get).
    var remembered: Bool = false

    private var symbolName: String {
        remembered ? "clock.arrow.circlepath" : "questionmark.circle.fill"
    }

    private var displayLabel: String { outcome.label(remembered: remembered) }
    private var displayHelp: String { outcome.helpText(remembered: remembered) }

    var body: some View {
        HStack(spacing: 2) {
            Image(systemName: symbolName)
                .font(.system(size: RuleMarkStyle.circleFillIconSize, weight: .semibold))
                .symbolRenderingMode(.monochrome)
            Text(displayLabel)
                .font(.caption.weight(.bold))
        }
        .foregroundStyle(outcome.color)
        .accessibilityLabel(displayHelp)
        .help(displayHelp)
    }
}

/// Compact mark for a field revealed by a matching Pass in Access preview.
struct PassRevealChip: View {
    let nick: String

    var body: some View {
        RuleFieldMarkChip(nick: nick, polarity: .pass)
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
    var helpText: String? = nil

    private var resolvedHelp: String {
        helpText ?? "Locked — grant does not allow this field"
    }

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
        .help(resolvedHelp)
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

// MARK: - Rule hit access log visuals

struct AccessLogRuleHitBadge: View {
    let polarity: RulePolarity
    let count: Int
    @Environment(\.backgroundProminence) private var backgroundProminence

    private var onProminentBackground: Bool {
        backgroundProminence == .increased
    }

    private var color: Color {
        polarity == .pass ? RuleMarkStyle.passGreen : RuleMarkStyle.blockRed
    }

    private var symbolName: String {
        polarity == .pass ? "checkmark.circle.fill" : "xmark.circle.fill"
    }

    private var accessibilityText: String {
        let label = polarity == .pass ? "Pass applied" : "Block applied"
        if count > 1 {
            return "\(label), \(count) hits"
        }
        return label
    }

    var body: some View {
        let ink = onProminentBackground ? Color.white : color
        HStack(spacing: 3) {
            Image(systemName: symbolName)
                .font(.system(size: RuleMarkStyle.circleFillIconSize, weight: .semibold))
                .symbolRenderingMode(.monochrome)
                .foregroundStyle(ink)
                .frame(height: 14)

            if count > 1 {
                Text("\(count)")
                    .font(.caption2.weight(.semibold).monospacedDigit())
                    .foregroundStyle(ink)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityText)
        .help(accessibilityText)
        .layoutPriority(1)
    }
}

// MARK: - Conditional Ask access log visuals

/// List-row chip: Ask allow/block — live popup (`?`) or Remember Ask reuse (`clock.arrow.circlepath`).
struct AccessLogConditionalAskBadge: View {
    let outcome: ConditionalFieldOutcome
    /// Fields decided with this outcome; shown when > 1.
    var count: Int = 1
    /// True when the decision came from Remember Ask (no popup on this get).
    var remembered: Bool = false
    @Environment(\.backgroundProminence) private var backgroundProminence

    private var onProminentBackground: Bool {
        backgroundProminence == .increased
    }

    private var color: Color { outcome.color }

    private var symbolName: String {
        remembered ? "clock.arrow.circlepath" : "questionmark.circle.fill"
    }

    private var accessibilityText: String {
        let base: String
        if remembered {
            base = outcome == .allowed ? "Ask: remembered allow" : "Ask: remembered block"
        } else {
            base = outcome == .allowed ? "Ask: user allowed" : "Ask: user blocked"
        }
        if count > 1 {
            return "\(base), \(count) fields"
        }
        return base
    }

    var body: some View {
        let ink = onProminentBackground ? Color.white : color
        HStack(spacing: 3) {
            Image(systemName: symbolName)
                .font(.system(size: RuleMarkStyle.circleFillIconSize, weight: .semibold))
                .symbolRenderingMode(.monochrome)
                .foregroundStyle(ink)
                .frame(height: 14)

            if count > 1 {
                Text("\(count)")
                    .font(.caption2.weight(.semibold).monospacedDigit())
                    .foregroundStyle(ink)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityText)
        .help(accessibilityText)
        .layoutPriority(1)
    }
}

// MARK: - Leak guard access log visuals

/// Open scope for the Access Log detections panel (Variant A).
enum AccessLogLeakPanelScope: Equatable, Sendable {
    case all
    case subject
    case body
}

struct AccessLogLeakHitBadge: View {
    let count: Int
    /// Collapsed / list: shield chip + count. Expanded: `{shield} leak` chip + count.
    var compact: Bool = false
    /// When set, the badge is a button that toggles the detections panel.
    var action: (() -> Void)? = nil
    /// Visual “pressed / open” chrome when the panel is showing this badge’s scope.
    var expanded: Bool = false
    @Environment(\.backgroundProminence) private var backgroundProminence

    private var onProminentBackground: Bool {
        backgroundProminence == .increased
    }

    var body: some View {
        let ink = onProminentBackground ? Color.white : WithheldStyle.text
        let chip = HStack(spacing: 3) {
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
            .foregroundStyle(ink)
            .padding(.horizontal, compact ? 4 : 5)
            .frame(height: 14)
            .background(
                Capsule().fill(chipFill)
            )
            .overlay {
                Capsule().strokeBorder(chipBorder, lineWidth: 0.5)
            }
            .shadow(
                color: expanded && !onProminentBackground
                    ? WithheldStyle.border.opacity(0.45)
                    : .clear,
                radius: expanded ? 2 : 0
            )

            Text("\(count)")
                .font(.caption2.weight(.semibold).monospacedDigit())
                .foregroundStyle(ink)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityLabelText)
        .accessibilityAddTraits(action != nil ? .isButton : [])
        .accessibilityValue(expanded ? "Expanded" : "")
        .help("Leak guard detected \(count) sensitive part\(count == 1 ? "" : "s")")
        .layoutPriority(1)

        if let action {
            Button(action: action) { chip }
                .buttonStyle(.plain)
        } else {
            chip
        }
    }

    private var chipFill: Color {
        if onProminentBackground {
            return Color.white.opacity(expanded ? 0.32 : 0.22)
        }
        return expanded ? Color.purple.opacity(0.22) : WithheldStyle.fill
    }

    private var chipBorder: Color {
        onProminentBackground ? Color.white.opacity(0.75) : WithheldStyle.border
    }

    private var accessibilityLabelText: String {
        "Leak guard detected \(count) part\(count == 1 ? "" : "s")"
    }
}

struct LeakGuardDetectionsList: View {
    let detections: [AuditLeakDetection]

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(Array(detections.enumerated()), id: \.offset) { index, detection in
                LeakGuardDetectionRow(detection: detection, index: index + 1)
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
}

/// One leak hit: compact before → after + field badge; rule/mode + full secret expand on hover.
private struct LeakGuardDetectionRow: View {
    let detection: AuditLeakDetection
    let index: Int
    @State private var isHovering = false

    private static let codeFontSize: CGFloat = 9.5
    private static let badgeHeight: CGFloat = 14
    /// Secrets longer than this get a wrapped full-text block on hover.
    private static let expandThreshold = 40
    /// Soft-wrap long tokens that have no spaces (ZWSP every N graphemes).
    private static let wrapChunkSize = 24

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(alignment: .center, spacing: 8) {
                Text("\(index)")
                    .font(.system(size: 9, weight: .bold).monospacedDigit())
                    .foregroundStyle(WithheldStyle.text)
                    .frame(width: 16, height: 16)
                    .background(
                        Circle().fill(Color.purple.opacity(0.18))
                    )
                    .overlay {
                        Circle().strokeBorder(WithheldStyle.border, lineWidth: 0.5)
                    }
                    .accessibilityHidden(true)

                HStack(alignment: .center, spacing: 5) {
                    codeSnippet(displayOriginal, replacement: false, truncating: true)
                        .layoutPriority(0)
                    Text("→")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.tertiary)
                        .layoutPriority(1)
                    replacementView(truncating: true)
                        .layoutPriority(1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                fieldBadge
                    .layoutPriority(1)
            }

            if isHovering {
                VStack(alignment: .leading, spacing: 3) {
                    if shouldExpandOriginal {
                        codeSnippet(
                            softWrapped(displayOriginal),
                            replacement: false,
                            truncating: false
                        )
                    }
                    if shouldExpandReplacement {
                        codeSnippet(
                            softWrapped(displayReplacement),
                            replacement: true,
                            truncating: false
                        )
                    }
                    HStack(spacing: 5) {
                        Text(detection.label)
                            .font(.system(size: 8))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.tail)
                        modeBadge
                        Spacer(minLength: 0)
                    }
                }
                .padding(.leading, 24)
                .frame(maxWidth: .infinity, alignment: .leading)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .contentShape(Rectangle())
        .onHover { isHovering = $0 }
        .animation(.easeOut(duration: 0.12), value: isHovering)
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(minHeight: 18)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityText)
        .help(helpText)
    }

    private func codeSnippet(_ text: String, replacement: Bool, truncating: Bool) -> some View {
        Text(text)
            .font(.system(size: Self.codeFontSize).monospaced())
            .foregroundStyle(replacement ? WithheldStyle.text : .primary)
            .lineLimit(truncating ? 1 : nil)
            .truncationMode(.middle)
            .padding(.horizontal, 5)
            .padding(.vertical, 1)
            .background(
                RoundedRectangle(cornerRadius: 3)
                    .fill(replacement ? Color.purple.opacity(0.08) : Color(nsColor: .controlBackgroundColor))
            )
            .overlay {
                RoundedRectangle(cornerRadius: 3)
                    .strokeBorder(
                        replacement ? WithheldStyle.border : Color.secondary.opacity(0.28),
                        lineWidth: 0.5
                    )
            }
            // Expand the layout slot so long secrets truncate (or wrap) inside the card;
            // background stays sized to the text when the string is short.
            .frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)
            .fixedSize(horizontal: false, vertical: !truncating)
            .textSelection(.enabled)
    }

    /// Insert zero-width spaces so unbroken tokens wrap inside the card width.
    private func softWrapped(_ text: String) -> String {
        guard text.count > Self.wrapChunkSize else { return text }
        var result = ""
        result.reserveCapacity(text.count + text.count / Self.wrapChunkSize)
        var count = 0
        for character in text {
            if count == Self.wrapChunkSize {
                result.append("\u{200B}")
                count = 0
            }
            result.append(character)
            count += 1
        }
        return result
    }

    private var fieldBadge: some View {
        let title: String = {
            if detection.field == .body, let line = detection.line {
                return "Body:\(line)"
            }
            return fieldTitle(detection.field)
        }()
        return HStack(spacing: 3) {
            Image(systemName: "doc.text")
                .font(.system(size: 8, weight: .semibold))
            Text(title)
                .font(.system(size: 8, weight: .semibold))
        }
        .foregroundStyle(WithheldStyle.text)
        .padding(.horizontal, 5)
        .frame(height: Self.badgeHeight)
        .background(Capsule().fill(Color.purple.opacity(0.10)))
        .overlay {
            Capsule().strokeBorder(WithheldStyle.border, lineWidth: 0.5)
        }
        .fixedSize(horizontal: true, vertical: false)
        .help(
            {
                if detection.field == .body, let line = detection.line {
                    return "Body line \(line)"
                }
                return fieldTitle(detection.field)
            }()
        )
    }

    private var modeBadge: some View {
        let meta = modeMeta
        return HStack(spacing: 3) {
            Image(systemName: meta.systemImage)
                .font(.system(size: 8, weight: .semibold))
            Text(meta.title)
                .font(.system(size: 8, weight: .semibold))
        }
        .foregroundStyle(meta.foreground)
        .padding(.horizontal, 5)
        .frame(height: Self.badgeHeight)
        .background(Capsule().fill(meta.fill))
        .overlay {
            Capsule()
                .strokeBorder(meta.border, style: StrokeStyle(lineWidth: 0.5, dash: meta.dashed ? [3, 2] : []))
        }
        .fixedSize(horizontal: true, vertical: false)
        .help(modeTitle)
    }

    private var modeMeta: (
        title: String,
        systemImage: String,
        foreground: Color,
        fill: Color,
        border: Color,
        dashed: Bool
    ) {
        switch detection.disposition {
        case .redacted:
            return (
                "redacted",
                "eye.slash.fill",
                .white,
                LeakGuardStyle.ink,
                LeakGuardStyle.ink,
                false
            )
        case .replaced where !detection.discloseToAgent:
            return (
                "stealth",
                "shield.slash.fill",
                WithheldStyle.text.opacity(0.85),
                Color.purple.opacity(0.08),
                WithheldStyle.border,
                false
            )
        case .replaced:
            return (
                "replaced",
                "arrow.left.arrow.right",
                WithheldStyle.text,
                Color.white,
                WithheldStyle.border,
                true
            )
        case .withheld:
            return (
                "withheld",
                "shield.slash.fill",
                WithheldStyle.text.opacity(0.85),
                Color.purple.opacity(0.08),
                WithheldStyle.border,
                false
            )
        }
    }

    private func fieldTitle(_ field: AuditLeakDetection.Field) -> String {
        switch field {
        case .subject: "Subject"
        case .body: "Body"
        }
    }

    private var modeTitle: String {
        switch detection.disposition {
        case .redacted:
            return "redacted"
        case .replaced:
            return detection.discloseToAgent ? "replaced" : "stealth replace"
        case .withheld:
            return "withheld"
        }
    }

    private var displayOriginal: String {
        let collapsed = collapseWhitespace(detection.original)
        return collapsed.isEmpty ? detection.label : collapsed
    }

    private var displayReplacement: String {
        let raw = detection.replacement.trimmingCharacters(in: .whitespacesAndNewlines)
        return raw.isEmpty ? "…" : raw
    }

    private var shouldExpandOriginal: Bool {
        displayOriginal.count > Self.expandThreshold
    }

    private var shouldExpandReplacement: Bool {
        guard case .replaced = detection.disposition else { return false }
        return displayReplacement.count > Self.expandThreshold
    }

    private func collapseWhitespace(_ raw: String) -> String {
        raw.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "\r\n", with: " ")
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "\r", with: " ")
    }

    @ViewBuilder
    private func replacementView(truncating: Bool) -> some View {
        switch detection.disposition {
        case .redacted:
            RedactedTokenChip()
        case .replaced:
            codeSnippet(displayReplacement, replacement: true, truncating: truncating)
        case .withheld:
            WithheldLabel(rules: [detection.label])
        }
    }

    private var accessibilityText: String {
        let whereField: String = {
            if detection.field == .body, let line = detection.line {
                return "Body line \(line)"
            }
            return fieldTitle(detection.field)
        }()
        let original = displayOriginal
        switch detection.disposition {
        case .redacted:
            return "\(whereField), \(detection.label), \(modeTitle): \(original) redacted"
        case .replaced:
            return "\(whereField), \(detection.label), \(modeTitle): \(original) to \(detection.replacement)"
        case .withheld:
            return "\(whereField), \(detection.label), \(modeTitle): \(original)"
        }
    }

    private var helpText: String {
        let field: String = {
            if detection.field == .body, let line = detection.line {
                return "Body:\(line)"
            }
            return fieldTitle(detection.field)
        }()
        return "\(field) · \(detection.label) · \(modeTitle)"
    }
}

/// Inverse-purple chip for `[REDACTED]` in leak-detection rows (matches code snippet size).
struct RedactedTokenChip: View {
    var body: some View {
        Text("[REDACTED]")
            .font(.system(size: 9.5, weight: .semibold).monospaced())
            .foregroundStyle(.white)
            .padding(.horizontal, 5)
            .padding(.vertical, 1)
            .background(LeakGuardStyle.ink, in: RoundedRectangle(cornerRadius: 3))
            .overlay {
                RoundedRectangle(cornerRadius: 3)
                    .strokeBorder(LeakGuardStyle.ink, lineWidth: 0.5)
            }
            .fixedSize(horizontal: true, vertical: false)
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
