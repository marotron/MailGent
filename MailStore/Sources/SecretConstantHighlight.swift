import Foundation

/// Build HTML for human confirm preview: escape plain text and wrap resolved spans in `<mark>`.
public enum SecretConstantHighlight {
    /// Matches `FlowUsedSecrets` chip fill — muted orange, not browser default yellow.
    public static let markBackgroundCSS = "rgba(255, 149, 0, 0.35)"
    public static let markUpdatedBackgroundCSS = "rgba(255, 149, 0, 0.55)"

    public static func html(resolved: String, spans: [SecretConstantResolveSpan]) -> String {
        guard !spans.isEmpty else {
            return escape(resolved).replacingOccurrences(of: "\n", with: "<br>")
        }
        var parts: [String] = [
            "<style>mark{background:\(markBackgroundCSS);color:inherit;border-radius:3px;padding:0 2px}mark.updated{background:\(markUpdatedBackgroundCSS)}</style>",
        ]
        var cursor = 0
        let chars = Array(resolved)
        for span in spans.sorted(by: { $0.start < $1.start }) {
            let start = max(0, min(span.start, chars.count))
            let end = max(start, min(span.end, chars.count))
            if cursor < start {
                parts.append(escape(String(chars[cursor..<start])))
            }
            let marked = escape(String(chars[start..<end]))
            let updatedClass = span.updatedSinceDraft ? " class=\"updated\"" : ""
            let title = escape("Secret constant [[mg:\(span.name)]]")
            parts.append("<mark\(updatedClass) title=\"\(title)\">\(marked)</mark>")
            cursor = end
        }
        if cursor < chars.count {
            parts.append(escape(String(chars[cursor...])))
        }
        return parts.joined().replacingOccurrences(of: "\n", with: "<br>")
    }

    private static func escape(_ text: String) -> String {
        text
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
    }
}
