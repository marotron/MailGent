import Foundation

/// Formats expanded context-thread detail for display.
/// Vault notes use Markdown; mail (and unknown) stay plain so email bodies do not break parsers.
public enum ContextThreadDetailText {
    public static func attributed(
        detail: String,
        original: ContextThreadOriginal?
    ) -> AttributedString {
        if case .vault = original {
            var options = AttributedString.MarkdownParsingOptions()
            options.interpretedSyntax = .full
            if let parsed = try? AttributedString(markdown: detail, options: options) {
                // `.full` stores block structure in presentation intents and strips `\n`
                // from the character buffer. SwiftUI `Text` ignores those intents, so
                // re-insert explicit breaks (and list bullets) for readable layout.
                return withExplicitBlockBreaks(parsed)
            }
        }
        return AttributedString(detail)
    }

    /// Turns presentation-intent blocks into newline-separated plain layout.
    static func withExplicitBlockBreaks(_ source: AttributedString) -> AttributedString {
        var result = AttributedString()
        var previousLeafID: Int?
        var previousWasHeader = false

        for run in source.runs {
            let intent = run.presentationIntent
            let leafID = intent?.components.first?.identity
            let header = isHeader(intent)
            let listItem = isListItem(intent)
            let startingNewBlock = leafID != previousLeafID

            if startingNewBlock {
                if !result.characters.isEmpty {
                    result.append(AttributedString((header || previousWasHeader) ? "\n\n" : "\n"))
                }
                if listItem {
                    result.append(AttributedString("• "))
                }
            }

            var chunk = AttributedString(source[run.range])
            if header {
                chunk.inlinePresentationIntent = .stronglyEmphasized
            }
            result.append(chunk)
            previousLeafID = leafID
            previousWasHeader = header
        }

        return result
    }

    private static func isHeader(_ intent: PresentationIntent?) -> Bool {
        intent?.components.contains {
            if case .header = $0.kind { return true }
            return false
        } ?? false
    }

    private static func isListItem(_ intent: PresentationIntent?) -> Bool {
        intent?.components.contains {
            if case .listItem = $0.kind { return true }
            return false
        } ?? false
    }
}
