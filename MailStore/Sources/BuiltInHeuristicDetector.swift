import Foundation

enum BuiltInHeuristicDetector {
    struct PatternSpec {
        let label: String
        let pattern: String
        let options: NSRegularExpression.Options
    }

    static func pattern(for cls: BuiltInLeakClass) -> PatternSpec {
        switch cls {
        case .apiKeys:
            return PatternSpec(
                label: "API keys",
                pattern: #"\b(sk-[a-zA-Z0-9_-]{8,}|AKIA[0-9A-Z]{16}|ghp_[a-zA-Z0-9]{20,})\b"#,
                options: []
            )
        case .jwt:
            return PatternSpec(
                label: "JWT tokens",
                pattern: #"\beyJ[a-zA-Z0-9_-]+\.[a-zA-Z0-9_-]+\.[a-zA-Z0-9_-]+\b"#,
                options: []
            )
        case .privateKeys:
            return PatternSpec(
                label: "Private keys",
                pattern: #"-----BEGIN [A-Z ]+ PRIVATE KEY-----[\s\S]*?-----END [A-Z ]+ PRIVATE KEY-----"#,
                options: [.dotMatchesLineSeparators]
            )
        case .passwordCtx:
            return PatternSpec(
                label: "Password patterns",
                pattern: #"\b(?:password|passwd|secret|token)\s*[:=]\s*\S+"#,
                options: [.caseInsensitive]
            )
        case .creditCards:
            return PatternSpec(
                label: "Credit cards",
                pattern: #"\b(?:\d[ -]*?){13,19}\b"#,
                options: []
            )
        case .ssn:
            return PatternSpec(
                label: "SSN",
                pattern: #"\b\d{3}-\d{2}-\d{4}\b"#,
                options: []
            )
        case .phones:
            return PatternSpec(
                label: "Phone numbers",
                pattern: #"\+?\d[\d\s().-]{8,}\d"#,
                options: []
            )
        case .emails:
            return PatternSpec(
                label: "Email addresses",
                pattern: #"\b[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}\b"#,
                options: []
            )
        }
    }

    static func collect(
        in text: String,
        enabledClasses: [BuiltInLeakClass: Bool]
    ) -> [LeakHitSpan] {
        var hits: [LeakHitSpan] = []
        for cls in BuiltInLeakClass.allCases {
            guard enabledClasses[cls] == true else { continue }
            let spec = pattern(for: cls)
            let spans = SpanFinder.regexSpans(in: text, pattern: spec.pattern, options: spec.options)
            let redactValue = "[REDACTED:\(cls.rawValue)]"
            for span in spans {
                hits.append(
                    LeakHitSpan(
                        start: span.start,
                        end: span.end,
                        label: spec.label,
                        source: "builtIn:\(cls.rawValue)",
                        action: .redact,
                        actionValue: redactValue,
                        discloseToAgent: true
                    )
                )
            }
        }
        return hits
    }
}
