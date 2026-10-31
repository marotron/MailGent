import Foundation
import MailStore
import Testing

struct SecretConstantHighlightTests {
    @Test func wrapsSpansInMark() {
        let html = SecretConstantHighlight.html(
            resolved: "Call +1-555 at home",
            spans: [
                SecretConstantResolveSpan(name: "phone_mobile", start: 5, end: 11, updatedSinceDraft: false),
            ]
        )
        #expect(html.contains("<mark title=\"Secret constant [[mg:phone_mobile]]\">+1-555</mark>"))
        #expect(html.contains("mark{background:\(SecretConstantHighlight.markBackgroundCSS)"))
        #expect(html.contains("Call "))
        #expect(html.contains(" at home"))
    }

    @Test func marksUpdatedSpans() {
        let html = SecretConstantHighlight.html(
            resolved: "x",
            spans: [
                SecretConstantResolveSpan(name: "a", start: 0, end: 1, updatedSinceDraft: true),
            ]
        )
        #expect(html.contains("<mark class=\"updated\" title=\"Secret constant [[mg:a]]\">x</mark>"))
        #expect(html.contains("mark.updated{background:\(SecretConstantHighlight.markUpdatedBackgroundCSS)"))
    }

    @Test func escapesHTML() {
        let html = SecretConstantHighlight.html(
            resolved: "a<b>&c",
            spans: []
        )
        #expect(html == "a&lt;b&gt;&amp;c")
    }
}
