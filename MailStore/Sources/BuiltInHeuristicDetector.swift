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
                // Optional leading `(` so `(44) 01252…` is one span (not `44)…`).
                pattern: #"\(?\+?\d[\d\s().-]{8,}\d"#,
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
            let redactValue = "[REDACTED:\(cls.rawValue)]"

            if cls == .passwordCtx {
                hits.append(contentsOf: passwordCtxHits(in: text, label: spec.label, redactValue: redactValue))
                continue
            }

            let spans = SpanFinder.regexSpans(in: text, pattern: spec.pattern, options: spec.options)
            for span in spans {
                let startIdx = text.index(text.startIndex, offsetBy: span.start)
                let endIdx = text.index(text.startIndex, offsetBy: span.end)
                let matched = String(text[startIdx..<endIdx])
                if cls == .phones, isPhoneFalsePositive(matched, in: text, at: span.start) { continue }
                if cls == .creditCards, !passesLuhn(digitsOnly(matched)) { continue }
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

    /// `password`/`passwd`/`secret` → value only; `token` → whole `token=…` assignment.
    private static func passwordCtxHits(
        in text: String,
        label: String,
        redactValue: String
    ) -> [LeakHitSpan] {
        let matches = passwordCtxRegex.matches(
            in: text,
            options: [],
            range: NSRange(text.startIndex..., in: text)
        )
        return matches.compactMap { match -> LeakHitSpan? in
            guard match.numberOfRanges >= 3,
                  let fullRange = Range(match.range(at: 0), in: text),
                  let prefixRange = Range(match.range(at: 1), in: text),
                  let valueRange = Range(match.range(at: 2), in: text)
            else { return nil }

            let prefix = String(text[prefixRange]).lowercased()
            let target = prefix.hasPrefix("token") ? fullRange : valueRange
            let start = text.distance(from: text.startIndex, to: target.lowerBound)
            let end = text.distance(from: text.startIndex, to: target.upperBound)
            return LeakHitSpan(
                start: start,
                end: end,
                label: label,
                source: "builtIn:passwordCtx",
                action: .redact,
                actionValue: redactValue,
                discloseToAgent: true
            )
        }
    }

    private static let passwordCtxRegex: NSRegularExpression = {
        // Group 1 = keyword + separator; group 2 = secret value.
        let pattern = #"\b((?:password|passwd|secret|token)\s*[:=]\s*)(\S+)"#
        return try! NSRegularExpression(pattern: pattern, options: [.caseInsensitive])
    }()

    private static func digitsOnly(_ text: String) -> String {
        String(text.unicodeScalars.filter { CharacterSet.decimalDigits.contains($0) }.map(Character.init))
    }

    private static func passesLuhn(_ digits: String) -> Bool {
        guard (13...19).contains(digits.count), digits.allSatisfy(\.isNumber) else { return false }
        var sum = 0
        for (index, character) in digits.reversed().enumerated() {
            guard let digit = character.wholeNumberValue else { return false }
            if index % 2 == 1 {
                let doubled = digit * 2
                sum += doubled > 9 ? doubled - 9 : doubled
            } else {
                sum += digit
            }
        }
        return sum % 10 == 0
    }

    /// Dates, money/score ranges, registry IDs, and other digit runs the loose phone regex over-matches.
    private static func isPhoneFalsePositive(_ matched: String, in text: String, at start: Int) -> Bool {
        let trimmed = matched.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return true }

        let digitCount = trimmed.unicodeScalars.filter { CharacterSet.decimalDigits.contains($0) }.count
        if digitCount < 7 || digitCount > 15 { return true }

        // Bare meeting/account IDs: optional + then 13+ digits, no separators.
        if bareLongIdPhoneRegex.firstMatch(
            in: trimmed,
            options: [],
            range: NSRange(trimmed.startIndex..., in: trimmed)
        ) != nil {
            return true
        }

        if dateLikePhoneRegex.firstMatch(
            in: trimmed,
            options: [],
            range: NSRange(trimmed.startIndex..., in: trimmed)
        ) != nil {
            return true
        }

        if decimalRangePhoneRegex.firstMatch(
            in: trimmed,
            options: [],
            range: NSRange(trimmed.startIndex..., in: trimmed)
        ) != nil {
            return true
        }

        // Dotted money/amounts (12.71) but not US-style phones (415.555.2671).
        if trimmed.contains("."), !looksLikeDottedPhone(trimmed) {
            let moneyish = trimmed.range(
                of: #"\d+\.\d{1,2}"#,
                options: .regularExpression
            ) != nil
            if moneyish { return true }
        }

        if hasRegistryLeftContext(in: text, before: start) {
            return true
        }

        return false
    }

    /// ~40 chars before the match: VAT / company registry labels (not a checksum validator).
    private static func hasRegistryLeftContext(in text: String, before start: Int) -> Bool {
        guard start > 0 else { return false }
        let endIdx = text.index(text.startIndex, offsetBy: start)
        let windowChars = min(40, start)
        let startIdx = text.index(endIdx, offsetBy: -windowChars)
        let prefix = String(text[startIdx..<endIdx])
        return registryPhoneContextRegex.firstMatch(
            in: prefix,
            options: [],
            range: NSRange(prefix.startIndex..., in: prefix)
        ) != nil
    }

    private static func looksLikeDottedPhone(_ text: String) -> Bool {
        dottedPhoneRegex.firstMatch(
            in: text,
            options: [],
            range: NSRange(text.startIndex..., in: text)
        ) != nil
    }

    private static let bareLongIdPhoneRegex: NSRegularExpression = {
        try! NSRegularExpression(pattern: #"^\+?\d{13,}$"#)
    }()

    private static let dateLikePhoneRegex: NSRegularExpression = {
        // 26-10-2026 14 | 2026-10-26 | 26.10.2026 14:30
        let pattern =
            #"^\d{1,4}[-./]\d{1,2}[-./]\d{1,4}(?:\s+\d{1,2}(?::\d{2}){0,2})?$"#
        return try! NSRegularExpression(pattern: pattern)
    }()

    private static let decimalRangePhoneRegex: NSRegularExpression = {
        // 12.71 - 12.71 (salary / score ranges)
        let pattern = #"^\d+\.\d{1,2}\s*[-–—]\s*\d+\.\d{1,2}$"#
        return try! NSRegularExpression(pattern: pattern)
    }()

    private static let dottedPhoneRegex: NSRegularExpression = {
        let pattern = #"^\+?\d{1,3}(?:\.\d{2,4}){2,4}$"#
        return try! NSRegularExpression(pattern: pattern)
    }()

    private static let registryPhoneContextRegex: NSRegularExpression = {
        // Left-window labels for VAT / company registry digit runs.
        let pattern =
            #"(?:VAT(?:\s*(?:No\.?|Number))?|Registered\s+in\s+England(?:\s+No\.?)?|Company\s+No(?:\.|mber)?|Reg\.?\s*No\.?|\bGB)\s*$"#
        return try! NSRegularExpression(pattern: pattern, options: [.caseInsensitive])
    }()
}
