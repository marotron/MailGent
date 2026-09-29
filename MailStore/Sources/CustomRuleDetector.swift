import Foundation

enum CustomRuleDetector {
    static func collect(in text: String, rules: [CustomLeakRule]) -> [LeakHitSpan] {
        var hits: [LeakHitSpan] = []
        for rule in rules where rule.enabled {
            let spans = spans(for: rule, in: text)
            let defaultRedact = "[REDACTED:\(rule.label)]"
            for span in spans {
                hits.append(
                    LeakHitSpan(
                        start: span.start,
                        end: span.end,
                        label: rule.label,
                        source: "custom:\(rule.id)",
                        action: rule.action,
                        actionValue: rule.actionValue.isEmpty ? defaultRedact : rule.actionValue,
                        discloseToAgent: rule.action == .redact ? true : rule.discloseToAgent
                    )
                )
            }
        }
        return hits
    }

    private static func spans(for rule: CustomLeakRule, in text: String) -> [(start: Int, end: Int)] {
        switch rule.kind {
        case .literal:
            return SpanFinder.literalSpans(in: text, needle: rule.pattern, caseInsensitive: rule.caseInsensitive)
        case .wildcard:
            let pattern = wildcardToRegex(rule.pattern)
            let options: NSRegularExpression.Options = rule.caseInsensitive ? [.caseInsensitive] : []
            return SpanFinder.regexSpans(in: text, pattern: pattern, options: options)
        case .regex:
            let options: NSRegularExpression.Options = rule.caseInsensitive ? [.caseInsensitive] : []
            return SpanFinder.regexSpans(in: text, pattern: rule.pattern, options: options)
        }
    }

    private static func wildcardToRegex(_ glob: String) -> String {
        var out = ""
        for ch in glob {
            switch ch {
            case "*": out += ".*"
            case "?": out += "."
            case ".", "+", "^", "$", "{", "}", "(", ")", "|", "[", "]", "\\":
                out.append("\\")
                out.append(ch)
            default:
                out.append(ch)
            }
        }
        return out
    }
}

enum SpanFinder {
    static func literalSpans(
        in text: String,
        needle: String,
        caseInsensitive: Bool
    ) -> [(start: Int, end: Int)] {
        guard !needle.isEmpty else { return [] }
        var hits: [(start: Int, end: Int)] = []
        let haystack = caseInsensitive ? text.lowercased() : text
        let needleNorm = caseInsensitive ? needle.lowercased() : needle
        var searchStart = haystack.startIndex
        while searchStart < haystack.endIndex,
              let range = haystack.range(of: needleNorm, range: searchStart..<haystack.endIndex)
        {
            let start = haystack.distance(from: haystack.startIndex, to: range.lowerBound)
            let end = start + needleNorm.count
            hits.append((start, end))
            searchStart = haystack.index(range.lowerBound, offsetBy: max(needleNorm.count, 1))
        }
        return hits
    }

    static func regexSpans(
        in text: String,
        pattern: String,
        options: NSRegularExpression.Options = []
    ) -> [(start: Int, end: Int)] {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: options) else {
            return []
        }
        let nsText = text as NSString
        let fullRange = NSRange(location: 0, length: nsText.length)
        let matches = regex.matches(in: text, options: [], range: fullRange)
        return matches.map { match in
            (match.range.location, match.range.location + match.range.length)
        }
    }
}
