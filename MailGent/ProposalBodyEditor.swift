import AppKit
import MailStore
import SwiftUI

/// Plain-text body with atomic secret pills. SwiftUI `TextEditor` cannot hold those tokens.
struct ProposalBodyEditor: NSViewRepresentable {
    @Binding var tokenized: String
    var constants: [SecretConstant]
    var agentID: String
    var pins: [ProposalPin]
    /// Replacement passages to mark in this body (prototype `mark.chg`).
    var changedPassages: [String] = []
    /// Row/cue focus selects and reveals this exact tokenized passage.
    var focusedPassage: String? = nil
    var focusRequest = 0
    var shortcut: ProposalReferShortcut
    var isEditable = true
    var fontScale: CGFloat = 1
    var onRefer: (String) -> Void

    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSScrollView()
        scroll.hasVerticalScroller = true
        scroll.drawsBackground = false
        scroll.borderType = .noBorder
        let textView = ProposalBodyTextView()
        textView.isRichText = true
        textView.importsGraphics = false
        textView.allowsUndo = true
        textView.isEditable = isEditable
        textView.isSelectable = true
        textView.drawsBackground = false
        textView.font = .systemFont(ofSize: 13 * fontScale)
        // ≈ CSS line-height 1.5 at 13px (SF natural line ≈ 15.5px → 19.5px).
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineSpacing = 4 * fontScale
        textView.defaultParagraphStyle = paragraph
        textView.textContainerInset = NSSize(width: 2, height: 4)
        textView.delegate = context.coordinator
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.textContainer?.widthTracksTextView = true
        textView.minSize = NSSize(width: 0, height: 80)
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        scroll.documentView = textView
        context.coordinator.textView = textView
        context.coordinator.parent = self
        context.coordinator.install(tokenized)
        context.coordinator.focusPassage(focusedPassage, request: focusRequest)
        context.coordinator.startShortcutMonitor()
        return scroll
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        context.coordinator.parent = self
        context.coordinator.shortcut = shortcut
        context.coordinator.textView?.isEditable = isEditable
        let current = context.coordinator.readTokenized()
        let scaleChanged = abs((context.coordinator.installedFontScale ?? fontScale) - fontScale) > 0.001
        if current != tokenized || scaleChanged {
            context.coordinator.install(tokenized)
        } else {
            context.coordinator.refreshMarks()
        }
        context.coordinator.focusPassage(focusedPassage, request: focusRequest)
    }

    static func dismantleNSView(_ nsView: NSScrollView, coordinator: Coordinator) {
        coordinator.stopShortcutMonitor()
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    @MainActor
    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: ProposalBodyEditor
        var shortcut: ProposalReferShortcut
        weak var textView: NSTextView?
        private var updating = false
        private var monitor: Any?
        private var bubble: NSButton?
        private var lastFocusedPassage: String?
        private var lastFocusRequest = -1
        fileprivate var installedFontScale: CGFloat?

        init(parent: ProposalBodyEditor) {
            self.parent = parent
            self.shortcut = parent.shortcut
        }

        func install(_ tokenized: String) {
            guard let textView, let storage = textView.textStorage else { return }
            updating = true
            let selected = textView.selectedRange()
            installedFontScale = parent.fontScale
            textView.font = .systemFont(ofSize: 13 * parent.fontScale)
            let paragraph = NSMutableParagraphStyle()
            paragraph.lineSpacing = 4 * parent.fontScale
            textView.defaultParagraphStyle = paragraph
            storage.setAttributedString(
                Self.attributed(
                    tokenized,
                    constants: parent.constants,
                    fontScale: parent.fontScale
                )
            )
            let length = storage.length
            let loc = min(selected.location, length)
            textView.setSelectedRange(NSRange(location: loc, length: 0))
            updating = false
            refreshMarks()
        }

        func readTokenized() -> String {
            guard let storage = textView?.textStorage else { return parent.tokenized }
            var out = ""
            storage.enumerateAttributes(in: NSRange(location: 0, length: storage.length)) { attrs, range, _ in
                if let attachment = attrs[.attachment] as? ProposalTokenAttachment {
                    out += SecretConstantPlaceholders.token(for: attachment.tokenName)
                } else if attrs[.attachment] == nil {
                    out += (storage.string as NSString).substring(with: range)
                }
            }
            return ProposalBodyTokens.literalsToTokens(out, constants: parent.constants, agentID: parent.agentID)
        }

        func textDidChange(_ notification: Notification) {
            guard !updating else { return }
            let next = readTokenized()
            if next != parent.tokenized {
                parent.tokenized = next
            }
            let raw = rawRead()
            if raw != next {
                install(next)
            }
            refreshMarks()
        }

        func textViewDidChangeSelection(_ notification: Notification) {
            placeBubble()
        }

        func textView(_ view: NSTextView, menu: NSMenu, for event: NSEvent, at charIndex: Int) -> NSMenu? {
            let item = NSMenuItem(
                title: "Refer to agent's attention",
                action: #selector(referFromMenu(_:)),
                keyEquivalent: shortcut.key
            )
            item.keyEquivalentModifierMask = shortcut.modifierMask
            item.target = self
            menu.insertItem(item, at: 0)
            return menu
        }

        @objc func referFromMenu(_ sender: Any?) {
            referSelection()
        }

        func startShortcutMonitor() {
            guard monitor == nil else { return }
            monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
                // Local key monitors for this window run on the main thread.
                guard let self else { return event }
                let characters = event.charactersIgnoringModifiers
                let modifiers = event.modifierFlags
                let handled = MainActor.assumeIsolated { () -> Bool in
                    guard let textView = self.textView else { return false }
                    guard textView.window?.firstResponder === textView else { return false }
                    guard self.shortcut.matches(
                        characters: characters,
                        modifierFlags: modifiers
                    ) else {
                        return false
                    }
                    self.referSelection()
                    return true
                }
                return handled ? nil : event
            }
        }

        func stopShortcutMonitor() {
            if let monitor {
                NSEvent.removeMonitor(monitor)
                self.monitor = nil
            }
        }

        func refreshMarks() {
            guard let textView, let storage = textView.textStorage else { return }
            updating = true
            removeReferenceMarkers(from: storage)
            let full = NSRange(location: 0, length: storage.length)
            storage.removeAttribute(.backgroundColor, range: full)
            storage.removeAttribute(.underlineStyle, range: full)
            storage.removeAttribute(.underlineColor, range: full)
            storage.addAttribute(.foregroundColor, value: NSColor.labelColor, range: full)
            let tokenized = readTokenized()
            let changeColor = NSColor(srgbRed: 36.0 / 255, green: 138.0 / 255, blue: 61.0 / 255, alpha: 1)
            for passage in parent.changedPassages where !passage.isEmpty {
                guard let range = tokenized.range(of: passage) else { continue }
                let start = tokenized.distance(from: tokenized.startIndex, to: range.lowerBound)
                let end = tokenized.distance(from: tokenized.startIndex, to: range.upperBound)
                if let display = displayRange(tokenStart: start, tokenEnd: end) {
                    let active = passage == parent.focusedPassage
                    storage.addAttribute(
                        .backgroundColor,
                        value: active ? changeColor : changeColor.withAlphaComponent(0.14),
                        range: display
                    )
                    storage.addAttribute(
                        .foregroundColor,
                        value: active ? NSColor.white : NSColor.labelColor,
                        range: display
                    )
                }
            }
            for pin in parent.pins {
                guard !pin.quote.isEmpty, let range = tokenized.range(of: pin.quote) else { continue }
                let start = tokenized.distance(from: tokenized.startIndex, to: range.lowerBound)
                let end = tokenized.distance(from: tokenized.startIndex, to: range.upperBound)
                if let display = displayRange(tokenStart: start, tokenEnd: end) {
                    let active = pin.quote == parent.focusedPassage
                    storage.addAttribute(
                        .backgroundColor,
                        value: active
                            ? NSColor(srgbRed: 0.42, green: 0.25, blue: 0.82, alpha: 1)
                            : NSColor(srgbRed: 0.937, green: 0.910, blue: 1, alpha: 1),
                        range: display
                    )
                    storage.addAttribute(
                        .foregroundColor,
                        value: active
                            ? NSColor.white
                            : NSColor(srgbRed: 0.290, green: 0.165, blue: 0.627, alpha: 1),
                        range: display
                    )
                }
            }
            updating = false
            placeBubble()
        }

        func focusPassage(_ passage: String?) {
            focusPassage(passage, request: lastFocusRequest &+ 1)
        }

        func focusPassage(_ passage: String?, request: Int) {
            guard request != lastFocusRequest || passage != lastFocusedPassage else { return }
            lastFocusRequest = request
            lastFocusedPassage = passage
            guard let passage, !passage.isEmpty, let textView else { return }
            let tokenized = readTokenized()
            guard let range = tokenized.range(of: passage) else { return }
            let start = tokenized.distance(from: tokenized.startIndex, to: range.lowerBound)
            let end = tokenized.distance(from: tokenized.startIndex, to: range.upperBound)
            guard let display = displayRange(tokenStart: start, tokenEnd: end) else { return }
            // Keep focus visual state in our attributes. A non-empty AppKit
            // selection paints system blue over the prototype's violet highlight.
            textView.setSelectedRange(NSRange(location: NSMaxRange(display), length: 0))
            textView.scrollRangeToVisible(display)
            bubble?.isHidden = true
            refreshMarks()
            bubble?.isHidden = true
        }

        private func removeReferenceMarkers(from storage: NSTextStorage) {
            var ranges: [NSRange] = []
            storage.enumerateAttribute(.attachment, in: NSRange(location: 0, length: storage.length)) { value, range, _ in
                if value is ProposalReferenceMarkerAttachment {
                    ranges.append(range)
                }
            }
            for range in ranges.reversed() {
                storage.deleteCharacters(in: range)
            }
        }

        private func referSelection() {
            guard let textView, let quote = selectedQuote() else { return }
            let insertionLocation = NSMaxRange(textView.selectedRange())
            parent.onRefer(quote)
            textView.setSelectedRange(NSRange(location: insertionLocation, length: 0))
            bubble?.isHidden = true
        }

        private func selectedQuote() -> String? {
            guard let textView, let storage = textView.textStorage else { return nil }
            let selected = textView.selectedRange()
            guard selected.length > 0 else { return nil }
            var cursor = 0
            var quoteStart: Int?
            var quoteEnd = 0
            storage.enumerateAttributes(in: NSRange(location: 0, length: storage.length)) { attrs, range, _ in
                let piece: String
                let atomic: Bool
                if let attachment = attrs[.attachment] as? ProposalTokenAttachment {
                    piece = SecretConstantPlaceholders.token(for: attachment.tokenName)
                    atomic = true
                } else if attrs[.attachment] is ProposalReferenceMarkerAttachment {
                    return
                } else {
                    piece = (storage.string as NSString).substring(with: range)
                    atomic = false
                }
                let overlap = NSIntersectionRange(range, selected)
                if overlap.length > 0 {
                    let localStart = overlap.location - range.location
                    if quoteStart == nil {
                        // The overlap's start in token-stream coordinates — not the
                        // run's start, or a whole-body run pins the quote at index 0.
                        quoteStart = atomic ? cursor : cursor + localStart
                    }
                    if atomic {
                        quoteEnd = cursor + piece.count
                    } else {
                        let local = (piece as NSString).substring(
                            with: NSRange(location: localStart, length: overlap.length)
                        )
                        quoteEnd = cursor + (piece as NSString).substring(to: localStart).count + local.count
                    }
                }
                cursor += piece.count
            }
            guard let quoteStart else { return nil }
            let snapped = ProposalBodyTokens.snap(in: readTokenized(), start: quoteStart, end: quoteEnd)
            let quote = ProposalBodyTokens.substring(readTokenized(), start: snapped.start, end: snapped.end)
            let trimmed = quote.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : trimmed
        }

        private func rawRead() -> String {
            guard let storage = textView?.textStorage else { return "" }
            var out = ""
            storage.enumerateAttributes(in: NSRange(location: 0, length: storage.length)) { attrs, range, _ in
                if let attachment = attrs[.attachment] as? ProposalTokenAttachment {
                    out += SecretConstantPlaceholders.token(for: attachment.tokenName)
                } else if attrs[.attachment] == nil {
                    out += (storage.string as NSString).substring(with: range)
                }
            }
            return out
        }

        private func displayRange(tokenStart: Int, tokenEnd: Int) -> NSRange? {
            guard let storage = textView?.textStorage else { return nil }
            var cursor = 0
            var displayStart: Int?
            var displayEnd = 0
            var found = false
            storage.enumerateAttributes(in: NSRange(location: 0, length: storage.length)) { attrs, range, stop in
                let piece: String
                let atomic: Bool
                if let attachment = attrs[.attachment] as? ProposalTokenAttachment {
                    piece = SecretConstantPlaceholders.token(for: attachment.tokenName)
                    atomic = true
                } else if attrs[.attachment] is ProposalReferenceMarkerAttachment {
                    return
                } else {
                    piece = (storage.string as NSString).substring(with: range)
                    atomic = false
                }
                let pieceEnd = cursor + piece.count
                if pieceEnd > tokenStart, cursor < tokenEnd {
                    // Map the quote's sub-range inside the piece — a plain run can
                    // span far beyond the quote, so highlight only the overlap.
                    // Atomic pills occupy one storage character; never use the
                    // token's Character count as an NSRange end (that OOBs).
                    // Plain offsets are Character-based and must become UTF-16
                    // before adding to range.location, or emoji splits a scalar.
                    if atomic {
                        if displayStart == nil { displayStart = range.location }
                        displayEnd = NSMaxRange(range)
                    } else {
                        let startInPiece = max(0, tokenStart - cursor)
                        let endInPiece = min(piece.count, tokenEnd - cursor)
                        let utf16Start = Self.utf16Offset(in: piece, characterOffset: startInPiece)
                        let utf16End = Self.utf16Offset(in: piece, characterOffset: endInPiece)
                        if displayStart == nil { displayStart = range.location + utf16Start }
                        displayEnd = range.location + utf16End
                    }
                    found = true
                }
                cursor = pieceEnd
                if cursor >= tokenEnd { stop.pointee = true }
            }
            guard found, let displayStart else { return nil }
            let end = min(max(displayStart, displayEnd), storage.length)
            let start = min(displayStart, end)
            let raw = NSRange(location: start, length: end - start)
            guard raw.length > 0 else { return raw }
            return (storage.string as NSString).rangeOfComposedCharacterSequences(for: raw)
        }

        /// Character offset → UTF-16 offset inside `string` (NSRange units).
        private static func utf16Offset(in string: String, characterOffset: Int) -> Int {
            let clamped = max(0, min(characterOffset, string.count))
            guard clamped > 0 else { return 0 }
            let index = string.index(string.startIndex, offsetBy: clamped)
            return string.utf16.distance(from: string.utf16.startIndex, to: index)
        }

        private func placeBubble() {
            guard let textView else { return }
            let button = bubble ?? {
                let button = NSButton(title: "", target: self, action: #selector(referFromMenu(_:)))
                button.bezelStyle = .recessed
                button.isBordered = false
                button.wantsLayer = true
                button.layer?.backgroundColor = NSColor(srgbRed: 0.42, green: 0.25, blue: 0.82, alpha: 1).cgColor
                button.layer?.cornerRadius = 10
                button.contentTintColor = .white
                button.font = .systemFont(ofSize: 11, weight: .semibold)
                textView.addSubview(button)
                bubble = button
                return button
            }()
            button.title = "Refer to agent's attention  \(shortcut.keycap)"
            button.sizeToFit()
            var frame = button.frame
            frame.size.width += 16
            frame.size.height = 22
            guard textView.selectedRange().length > 0 else {
                button.isHidden = true
                return
            }
            let screen = textView.firstRect(forCharacterRange: textView.selectedRange(), actualRange: nil)
            guard let window = textView.window else { return }
            let inWindow = window.convertFromScreen(screen)
            let local = textView.convert(inWindow, from: nil)
            frame.origin = NSPoint(x: local.minX, y: local.maxY + 4)
            button.frame = frame
            button.isHidden = false
        }

        private static func attributed(
            _ tokenized: String,
            constants: [SecretConstant],
            fontScale: CGFloat
        ) -> NSAttributedString {
            let result = NSMutableAttributedString()
            let font = NSFont.systemFont(ofSize: 13 * fontScale)
            // ≈ CSS line-height 1.5 at 13px (SF natural line ≈ 15.5px → 19.5px).
            let paragraph = NSMutableParagraphStyle()
            paragraph.lineSpacing = 4 * fontScale
            let plain: [NSAttributedString.Key: Any] = [
                .font: font,
                .foregroundColor: NSColor.labelColor,
                .paragraphStyle: paragraph,
            ]
            let catalog = Dictionary(uniqueKeysWithValues: constants.map { ($0.name, $0.value) })
            let matches = SecretConstantPlaceholders.find(in: tokenized)
            var cursor = 0
            let chars = Array(tokenized)
            for match in matches {
                if cursor < match.start {
                    result.append(NSAttributedString(
                        string: String(chars[cursor..<match.start]),
                        attributes: plain
                    ))
                }
                let display = catalog[match.name] ?? "[unknown]"
                let attachment = ProposalTokenAttachment(
                    name: match.name,
                    display: display,
                    fontScale: fontScale
                )
                let piece = NSMutableAttributedString(attachment: attachment)
                piece.addAttribute(.font, value: font, range: NSRange(location: 0, length: piece.length))
                piece.addAttribute(.paragraphStyle, value: paragraph, range: NSRange(location: 0, length: piece.length))
                result.append(piece)
                cursor = match.end
            }
            if cursor < chars.count {
                result.append(NSAttributedString(string: String(chars[cursor..<chars.count]), attributes: plain))
            }
            return result
        }
    }
}

private final class ProposalBodyTextView: NSTextView {
    override func paste(_ sender: Any?) {
        pasteAsPlainText(sender)
    }
}

final class ProposalTokenAttachment: NSTextAttachment {
    let tokenName: String

    init(name: String, display: String, fontScale: CGFloat = 1) {
        self.tokenName = name
        super.init(data: nil, ofType: nil)
        attachmentCell = ProposalTokenCell(display: display, fontScale: fontScale)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("not used")
    }
}

final class ProposalReferenceMarkerAttachment: NSTextAttachment {
    init(number: Int) {
        super.init(data: nil, ofType: nil)
        attachmentCell = ProposalReferenceMarkerCell(number: number)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("not used")
    }
}

private final class ProposalTokenCell: NSTextAttachmentCell {
    let display: String
    let fontScale: CGFloat

    /// Same size as plain body text so glyph baselines match on the line.
    private var tokenFont: NSFont { NSFont.systemFont(ofSize: 13 * fontScale) }
    private var horizontalPadding: CGFloat { 5 * fontScale }
    private var verticalPadding: CGFloat { 1.5 * fontScale }

    init(display: String, fontScale: CGFloat) {
        self.display = display
        self.fontScale = fontScale
        super.init(textCell: display)
    }

    @available(*, unavailable)
    required init(coder: NSCoder) {
        fatalError("not used")
    }

    override func cellSize() -> NSSize {
        let width = (display as NSString).size(withAttributes: [.font: tokenFont]).width
        let height = ceil(tokenFont.ascender - tokenFont.descender) + verticalPadding * 2
        return NSSize(width: ceil(width) + horizontalPadding * 2, height: height)
    }

    /// Pin the attachment baseline to the surrounding text baseline (not the cell mid-Y).
    override func cellBaselineOffset() -> NSPoint {
        NSPoint(x: 0, y: tokenFont.descender - verticalPadding)
    }

    override func draw(withFrame cellFrame: NSRect, in controlView: NSView?) {
        let path = NSBezierPath(
            roundedRect: cellFrame,
            xRadius: 4 * fontScale,
            yRadius: 4 * fontScale
        )
        NSColor(srgbRed: 1, green: 0.851, blue: 0.639, alpha: 1).setFill()
        path.fill()
        let color = NSColor(srgbRed: 0.420, green: 0.227, blue: 0, alpha: 1)
        let attrs: [NSAttributedString.Key: Any] = [
            .font: tokenFont,
            .foregroundColor: color,
        ]
        // Flipped NSTextView: origin is top-left; top padding keeps glyphs on the shared baseline.
        let origin = NSPoint(
            x: cellFrame.minX + horizontalPadding,
            y: cellFrame.minY + verticalPadding
        )
        (display as NSString).draw(at: origin, withAttributes: attrs)
    }
}

private final class ProposalReferenceMarkerCell: NSTextAttachmentCell {
    let number: Int

    init(number: Int) {
        self.number = number
        super.init(textCell: "\(number)")
    }

    @available(*, unavailable)
    required init(coder: NSCoder) {
        fatalError("not used")
    }

    override func cellSize() -> NSSize {
        NSSize(width: 14, height: 14)
    }

    override func draw(withFrame cellFrame: NSRect, in controlView: NSView?) {
        let rect = cellFrame.insetBy(dx: 1, dy: 1)
        NSColor(srgbRed: 0.42, green: 0.25, blue: 0.82, alpha: 1).setFill()
        NSBezierPath(ovalIn: rect).fill()
        let font = NSFont.systemFont(ofSize: 9, weight: .bold)
        let number = "\(number)" as NSString
        let size = number.size(withAttributes: [.font: font])
        number.draw(
            at: NSPoint(x: rect.midX - size.width / 2, y: rect.midY - size.height / 2),
            withAttributes: [.font: font, .foregroundColor: NSColor.white]
        )
    }
}

private extension ProposalReferShortcut {
    var modifierMask: NSEvent.ModifierFlags {
        var mask: NSEvent.ModifierFlags = []
        if command { mask.insert(.command) }
        if shift { mask.insert(.shift) }
        if option { mask.insert(.option) }
        if control { mask.insert(.control) }
        return mask
    }
}
