import AppKit
import MailStore
import SwiftUI
import Testing
@testable import MailGent

/// Regression: refer must capture the selected passage, not run from the top
/// of the (single-attribute-run) body to the selection end.
@MainActor
struct ProposalBodyEditorReferTests {
    private final class QuoteBox {
        var quotes: [String] = []
    }

    private func makeEditor(
        _ body: String,
        constants: [SecretConstant] = [],
        pins: [ProposalPin] = [],
        box: QuoteBox
    ) -> ProposalBodyEditor.Coordinator {
        var tokenized = body
        let editor = ProposalBodyEditor(
            tokenized: Binding(get: { tokenized }, set: { tokenized = $0 }),
            constants: constants,
            agentID: "test-agent",
            pins: pins,
            shortcut: .defaultShortcut,
            onRefer: { box.quotes.append($0) }
        )
        let coordinator = editor.makeCoordinator()
        // Plain NSTextView without a window is enough for install + refer.
        let textView = NSTextView(frame: NSRect(x: 0, y: 0, width: 400, height: 300))
        coordinator.textView = textView
        coordinator.install(body)
        return coordinator
    }

    @Test func referQuotesOnlyTheSelectedPassage() {
        let body = "Hi Sam,\n\nThanks for the introduction. Does Thursday work?\n\nBest,"
        // Select "Does Thursday" — storage location 38, length 13.
        let box = QuoteBox()
        let coordinator = makeEditor(body, box: box)
        coordinator.textView?.setSelectedRange(NSRange(location: 38, length: 13))
        coordinator.referFromMenu(nil)
        #expect(box.quotes == ["Does Thursday"])
    }

    @Test func referringCollapsesTheNativeSelectionSoThePinHighlightCanShow() {
        let body = "First passage. Second passage."
        let box = QuoteBox()
        let coordinator = makeEditor(body, box: box)
        coordinator.textView?.setSelectedRange(NSRange(location: 0, length: 13))

        coordinator.referFromMenu(nil)

        #expect(box.quotes == ["First passage"])
        #expect(coordinator.textView?.selectedRange() == NSRange(location: 13, length: 0))
    }

    @Test func referQuotesPassageAfterATokenPill() {
        let phone = SecretConstant(
            name: "phone",
            label: "Mobile",
            value: "+44 7501 222825",
            allowedAgentIDs: ["test-agent"]
        )
        let body = "Reach me at [[mg:phone]] today please."
        // The pill occupies one storage character; "today please" starts at 14.
        let box = QuoteBox()
        let coordinator = makeEditor(body, constants: [phone], box: box)
        coordinator.textView?.setSelectedRange(NSRange(location: 14, length: 12))
        coordinator.referFromMenu(nil)
        #expect(box.quotes == ["today please"])
    }

    @Test func pinHighlightCoversOnlyTheQuoteNotTheWholeRun() {
        let phone = SecretConstant(
            name: "phone",
            label: "Mobile",
            value: "+44 7501 222825",
            allowedAgentIDs: ["test-agent"]
        )
        // One plain attribute run spans from the top to the pill; the quote sits inside it.
        let body = "Hi Sam,\n\nThanks for the introduction on Tuesday. Reach me at [[mg:phone]] today."
        var tokenized = body
        let editor = ProposalBodyEditor(
            tokenized: Binding(get: { tokenized }, set: { tokenized = $0 }),
            constants: [phone],
            agentID: "test-agent",
            pins: [ProposalPin(id: "r1", quote: "introduction")],
            shortcut: .defaultShortcut,
            onRefer: { _ in }
        )
        let coordinator = editor.makeCoordinator()
        let textView = NSTextView(frame: NSRect(x: 0, y: 0, width: 400, height: 300))
        coordinator.textView = textView
        coordinator.install(body)
        var ranges: [NSRange] = []
        textView.textStorage?.enumerateAttribute(
            .backgroundColor,
            in: NSRange(location: 0, length: textView.textStorage?.length ?? 0)
        ) { value, range, _ in
            if value != nil { ranges.append(range) }
        }
        #expect(ranges == [NSRange(location: 24, length: 12)])
    }

    @Test func focusSquareUsesNoInlineNumberAndAvoidsNativeSelectionColor() {
        let body = "Hi [[mg:phone]] today."
        let phone = SecretConstant(
            name: "phone",
            label: "Mobile",
            value: "+44 7501 222825",
            allowedAgentIDs: ["test-agent"]
        )
        let box = QuoteBox()
        let coordinator = makeEditor(
            body,
            constants: [phone],
            pins: [ProposalPin(id: "r1", quote: "today")],
            box: box
        )

        guard let storage = coordinator.textView?.textStorage else {
            Issue.record("Expected editor text storage")
            return
        }
        var markerRanges: [NSRange] = []
        storage.enumerateAttribute(.attachment, in: NSRange(location: 0, length: storage.length)) { value, range, _ in
            if value is ProposalReferenceMarkerAttachment {
                markerRanges.append(range)
            }
        }
        #expect(markerRanges.isEmpty, "focus-square passages have no inline number")

        coordinator.parent.focusedPassage = "today"
        coordinator.focusPassage("today")
        // Collapse after the passage so AppKit's blue native selection cannot cover
        // the custom violet focus highlight.
        #expect(coordinator.textView?.selectedRange() == NSRange(location: 10, length: 0))
        var effectiveRange = NSRange()
        let color = storage.attribute(
            .backgroundColor,
            at: 5,
            effectiveRange: &effectiveRange
        ) as? NSColor
        #expect(effectiveRange == NSRange(location: 5, length: 5))
        #expect(color == NSColor(srgbRed: 0.42, green: 0.25, blue: 0.82, alpha: 1))
    }

    /// Crash regression (0.24.0 dogfood): referring a passage that includes a
    /// secret pill used the token's character length (`[[mg:phone]]` → 12) as an
    /// NSRange end on a 1-character attachment, and `addAttribute` trapped.
    @Test func pinHighlightAcrossSecretPillDoesNotTrap() {
        let phone = SecretConstant(
            name: "phone",
            label: "Mobile",
            value: "+44 7501 222825",
            allowedAgentIDs: ["test-agent"]
        )
        let body = "Reach me at [[mg:phone]] today please."
        let quote = "at [[mg:phone]] today"
        var tokenized = body
        let editor = ProposalBodyEditor(
            tokenized: Binding(get: { tokenized }, set: { tokenized = $0 }),
            constants: [phone],
            agentID: "test-agent",
            pins: [ProposalPin(id: "r1", quote: quote)],
            shortcut: .defaultShortcut,
            onRefer: { _ in }
        )
        let coordinator = editor.makeCoordinator()
        let textView = NSTextView(frame: NSRect(x: 0, y: 0, width: 400, height: 300))
        coordinator.textView = textView
        coordinator.install(body)

        guard let storage = textView.textStorage else {
            Issue.record("Expected editor text storage")
            return
        }
        // Tokenized quote is 21 Characters; storage span is "at " + pill + " today"
        // (3 + 1 + 6 = 10). Using the token length as an NSRange end would OOB.
        var ranges: [NSRange] = []
        storage.enumerateAttribute(
            .backgroundColor,
            in: NSRange(location: 0, length: storage.length)
        ) { value, range, _ in
            if value != nil { ranges.append(range) }
        }
        #expect(ranges == [NSRange(location: 9, length: 10)])
        #expect(NSMaxRange(ranges[0]) <= storage.length)
    }

    /// Crash regression: Character offsets must map to UTF-16 before becoming
    /// an NSRange, or a pin on/near emoji splits a surrogate and AppKit traps.
    @Test func pinHighlightOnEmojiDoesNotTrap() {
        let body = "Hello 👋 world"
        var tokenized = body
        let editor = ProposalBodyEditor(
            tokenized: Binding(get: { tokenized }, set: { tokenized = $0 }),
            constants: [],
            agentID: "test-agent",
            pins: [ProposalPin(id: "r1", quote: "👋")],
            shortcut: .defaultShortcut,
            onRefer: { _ in }
        )
        let coordinator = editor.makeCoordinator()
        let textView = NSTextView(frame: NSRect(x: 0, y: 0, width: 400, height: 300))
        coordinator.textView = textView
        coordinator.install(body)

        guard let storage = textView.textStorage else {
            Issue.record("Expected editor text storage")
            return
        }
        var ranges: [NSRange] = []
        storage.enumerateAttribute(
            .backgroundColor,
            in: NSRange(location: 0, length: storage.length)
        ) { value, range, _ in
            if value != nil { ranges.append(range) }
        }
        #expect(ranges == [NSRange(location: 6, length: 2)])
    }
}
