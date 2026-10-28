import Foundation
import MailStore
import Testing

@Suite struct ContextThreadDetailTextTests {
    @Test func vaultMarkdownStripsEmphasisMarkers() {
        let original = ContextThreadOriginal.vault(relativePath: "STATUS.md")
        let attributed = ContextThreadDetailText.attributed(
            detail: "**Company:** Spyrosoft",
            original: original
        )
        #expect(String(attributed.characters) == "Company: Spyrosoft")
        #expect(
            attributed.runs.contains { run in
                run.inlinePresentationIntent?.contains(.stronglyEmphasized) == true
            }
        )
    }

    @Test func vaultMarkdownPreservesBlockBreaksAndListBullets() {
        let original = ContextThreadOriginal.vault(relativePath: "STATUS.md")
        let detail = """
        # STATUS - Spyrosoft

        Last updated: 2026-10-28

        ## Role
        - **Company:** Spyrosoft
        - **Role:** Test Engineer
        """
        let attributed = ContextThreadDetailText.attributed(detail: detail, original: original)
        let text = String(attributed.characters)
        #expect(text.contains("STATUS - Spyrosoft\n\nLast updated: 2026-10-28"))
        #expect(text.contains("\n\nRole\n\n"))
        #expect(text.contains("• Company: Spyrosoft\n• Role: Test Engineer"))
        #expect(!text.contains("**"))
        #expect(!text.contains("#"))
    }

    @Test func vaultMarkdownKeepsLinks() {
        let original = ContextThreadOriginal.vault(relativePath: "STATUS.md")
        let attributed = ContextThreadDetailText.attributed(
            detail: "- **JD:** https://example.com/job",
            original: original
        )
        #expect(
            attributed.runs.contains { run in
                run.link == URL(string: "https://example.com/job")
            }
        )
    }

    @Test func mailDetailStaysPlainIncludingAsterisks() {
        let original = ContextThreadOriginal.mail(
            accountID: "a",
            placement: "INBOX",
            id: "1",
            internetMessageID: nil
        )
        let raw = "**Company:** Spyrosoft"
        let attributed = ContextThreadDetailText.attributed(detail: raw, original: original)
        #expect(String(attributed.characters) == raw)
    }

    @Test func nilOriginalStaysPlain() {
        let raw = "# Heading\n\n**bold**"
        let attributed = ContextThreadDetailText.attributed(detail: raw, original: nil)
        #expect(String(attributed.characters) == raw)
    }
}
