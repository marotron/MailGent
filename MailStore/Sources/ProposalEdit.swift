import Foundation

/// Word-level diff of a tokenized draft (prototype `diffHunks`).
public struct ProposalTextHunk: Equatable, Sendable {
    public let before: String
    public let after: String

    public init(before: String, after: String) {
        self.before = before
        self.after = after
    }
}

/// One word-diff hunk plus its UTF-16 ranges in the original strings (before trim).
public struct ProposalTextSpan: Equatable, Sendable {
    public let before: String
    public let after: String
    public let beforeStart: Int
    public let beforeEnd: Int
    public let afterStart: Int
    public let afterEnd: Int

    public init(before: String, after: String, beforeStart: Int, beforeEnd: Int, afterStart: Int, afterEnd: Int) {
        self.before = before
        self.after = after
        self.beforeStart = beforeStart
        self.beforeEnd = beforeEnd
        self.afterStart = afterStart
        self.afterEnd = afterEnd
    }
}

public struct ProposalFieldSwap: Equatable, Sendable {
    public let before: String
    public let after: String

    public init(before: String, after: String) {
        self.before = before
        self.after = after
    }
}

/// Agent-facing field diffs. Strings are already redacted.
public struct ProposalChanges: Equatable, Sendable {
    public var to: ProposalFieldSwap?
    public var cc: ProposalFieldSwap?
    public var bcc: ProposalFieldSwap?
    public var subject: ProposalFieldSwap?
    public var body: [ProposalTextHunk]

    public init(
        to: ProposalFieldSwap? = nil,
        cc: ProposalFieldSwap? = nil,
        bcc: ProposalFieldSwap? = nil,
        subject: ProposalFieldSwap? = nil,
        body: [ProposalTextHunk] = []
    ) {
        self.to = to
        self.cc = cc
        self.bcc = bcc
        self.subject = subject
        self.body = body
    }

    public var isEmpty: Bool {
        to == nil && cc == nil && bcc == nil && subject == nil && body.isEmpty
    }

    public var count: Int {
        [to, cc, bcc, subject].compactMap { $0 }.count + body.count
    }

    public func dictionary() -> [String: Any] {
        var out: [String: Any] = [:]
        if let to { out["to"] = ["before": to.before, "after": to.after] }
        if let cc { out["cc"] = ["before": cc.before, "after": cc.after] }
        if let bcc { out["bcc"] = ["before": bcc.before, "after": bcc.after] }
        if let subject { out["subject"] = ["before": subject.before, "after": subject.after] }
        if !body.isEmpty {
            out["body"] = body.map { ["before": $0.before, "after": $0.after] }
        }
        return out
    }
}

public enum ProposalBodyDiff {
    /// Word-level LCS. Short common gaps (≤3 words, no `.!?` or newline) merge into one hunk.
    public static func hunks(before: String, after: String) -> [ProposalTextHunk] {
        spans(before: before, after: after).map { ProposalTextHunk(before: $0.before, after: $0.after) }
    }

    /// Same hunks as `hunks`, with UTF-16 ranges into `before` / `after` before trimming.
    public static func spans(before: String, after: String) -> [ProposalTextSpan] {
        let aTokens = tokens(before)
        let bTokens = tokens(after)
        let n = aTokens.count
        let m = bTokens.count
        var dp = Array(repeating: Array(repeating: 0, count: m + 1), count: n + 1)
        if n > 0, m > 0 {
            for i in stride(from: n - 1, through: 0, by: -1) {
                for j in stride(from: m - 1, through: 0, by: -1) {
                    if aTokens[i] == bTokens[j] {
                        dp[i][j] = dp[i + 1][j + 1] + 1
                    } else {
                        dp[i][j] = max(dp[i + 1][j], dp[i][j + 1])
                    }
                }
            }
        }

        struct Raw {
            var aStart: Int
            var aEnd: Int
            var bStart: Int
            var bEnd: Int
            var before: String
            var after: String
        }

        var raw: [Raw] = []
        var i = 0
        var j = 0
        var offA = 0
        var offB = 0
        var bufA = ""
        var bufB = ""
        var aS: Int?
        var bS: Int?

        func flush() {
            if !bufA.isEmpty || !bufB.isEmpty {
                raw.append(
                    Raw(
                        aStart: aS ?? offA,
                        aEnd: offA,
                        bStart: bS ?? offB,
                        bEnd: offB,
                        before: trim(bufA),
                        after: trim(bufB)
                    )
                )
            }
            bufA = ""
            bufB = ""
            aS = nil
            bS = nil
        }

        while i < n || j < m {
            if i < n, j < m, aTokens[i] == bTokens[j] {
                flush()
                offA += utf16Length(aTokens[i])
                offB += utf16Length(bTokens[j])
                i += 1
                j += 1
            } else if j < m, i >= n || dp[i][j + 1] >= dp[i + 1][j] {
                if bS == nil { bS = offB }
                bufB += bTokens[j]
                offB += utf16Length(bTokens[j])
                j += 1
            } else {
                if aS == nil { aS = offA }
                bufA += aTokens[i]
                offA += utf16Length(aTokens[i])
                i += 1
            }
        }
        flush()

        struct Merged {
            var aStart: Int
            var aEnd: Int
            var bStart: Int
            var bEnd: Int
            var before: String
            var after: String
        }

        var merged: [Merged] = []
        for hunk in raw {
            if let prev = merged.last {
                let gap = slice(after, prev.bEnd, hunk.bStart)
                let trimmedGap = trim(gap)
                let gapWords = trimmedGap.isEmpty ? 0 : trimmedGap.split { $0.isWhitespace }.count
                let hasBreak = gap.contains(".") || gap.contains("!") || gap.contains("?") || gap.contains("\n")
                if !hasBreak, gapWords <= 3 {
                    merged[merged.count - 1] = Merged(
                        aStart: prev.aStart,
                        aEnd: hunk.aEnd,
                        bStart: prev.bStart,
                        bEnd: hunk.bEnd,
                        before: trim(slice(before, prev.aStart, hunk.aEnd)),
                        after: trim(slice(after, prev.bStart, hunk.bEnd))
                    )
                    continue
                }
            }
            merged.append(
                Merged(
                    aStart: hunk.aStart,
                    aEnd: hunk.aEnd,
                    bStart: hunk.bStart,
                    bEnd: hunk.bEnd,
                    before: hunk.before,
                    after: hunk.after
                )
            )
        }

        return merged
            .filter { $0.before != $0.after }
            .map {
                ProposalTextSpan(
                    before: $0.before,
                    after: $0.after,
                    beforeStart: $0.aStart,
                    beforeEnd: $0.aEnd,
                    afterStart: $0.bStart,
                    afterEnd: $0.bEnd
                )
            }
    }

    private static func tokens(_ text: String) -> [String] {
        guard !text.isEmpty,
              let regex = try? NSRegularExpression(pattern: #"\S+|\s+"#, options: [])
        else {
            return []
        }
        let ns = text as NSString
        return regex.matches(in: text, range: NSRange(location: 0, length: ns.length))
            .map { ns.substring(with: $0.range) }
    }

    private static func utf16Length(_ token: String) -> Int {
        (token as NSString).length
    }

    private static func slice(_ text: String, _ start: Int, _ end: Int) -> String {
        let ns = text as NSString
        let loc = max(0, min(start, ns.length))
        let upper = max(loc, min(end, ns.length))
        return ns.substring(with: NSRange(location: loc, length: upper - loc))
    }

    private static func trim(_ text: String) -> String {
        text.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

public enum ProposalEnvelopeDiff {
    public static func join(_ addresses: [String]) -> String {
        addresses
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: ", ")
    }

    public static func split(_ line: String) -> [String] {
        line.split(separator: ",", omittingEmptySubsequences: false)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    /// Full list before/after when the joined line changed. `redact` runs on both sides.
    public static func swap(before: [String], after: [String], redact: (String) -> String) -> ProposalFieldSwap? {
        let left = join(before)
        let right = join(after)
        guard left != right else { return nil }
        return ProposalFieldSwap(before: redact(left), after: redact(right))
    }

    public static func swap(before: String, after: String, redact: (String) -> String) -> ProposalFieldSwap? {
        let left = before.trimmingCharacters(in: .whitespacesAndNewlines)
        let right = after.trimmingCharacters(in: .whitespacesAndNewlines)
        guard left != right else { return nil }
        return ProposalFieldSwap(before: redact(left), after: redact(right))
    }

    /// Addresses in `after` that were not in `before` (trim, case-insensitive).
    public static func added(before: [String], after: [String]) -> [String] {
        let prior = Set(before.map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() })
        var seen = Set<String>()
        var out: [String] = []
        for raw in after {
            let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }
            let key = trimmed.lowercased()
            guard !prior.contains(key), seen.insert(key).inserted else { continue }
            out.append(trimmed)
        }
        return out
    }
}

public enum ProposalBodyTokens {
    /// Allowlisted constant values typed into the body become `{{mg:name}}`. Longer values win.
    /// Existing tokens are left alone. Envelope fields must not call this.
    public static func literalsToTokens(
        _ text: String,
        constants: [SecretConstant],
        agentID: String
    ) -> String {
        let allowed = constants
            .filter { constant in
                !constant.value.isEmpty && constant.allowedAgentIDs.contains(agentID)
            }
            .sorted { $0.value.count > $1.value.count }
        guard !allowed.isEmpty else { return text }

        let matches = SecretConstantPlaceholders.find(in: text)
        var cursor = 0
        var out = ""
        let chars = Array(text)
        for match in matches {
            if cursor < match.start {
                out += replaceLiterals(String(chars[cursor..<match.start]), allowed: allowed)
            }
            out += SecretConstantPlaceholders.token(for: match.name)
            cursor = match.end
        }
        if cursor < chars.count {
            out += replaceLiterals(String(chars[cursor..<chars.count]), allowed: allowed)
        }
        return out
    }

    /// Expand `start..<end` (character offsets) to cover any `{{mg:name}}` it touches.
    public static func snap(in text: String, start: Int, end: Int) -> (start: Int, end: Int) {
        guard end > start else { return (start, end) }
        var lo = start
        var hi = end
        for match in SecretConstantPlaceholders.find(in: text) {
            if hi > match.start, lo < match.end {
                lo = min(lo, match.start)
                hi = max(hi, match.end)
            }
        }
        return (lo, hi)
    }

    public static func substring(_ text: String, start: Int, end: Int) -> String {
        let chars = Array(text)
        let lo = max(0, min(start, chars.count))
        let hi = max(lo, min(end, chars.count))
        return String(chars[lo..<hi])
    }

    private static func replaceLiterals(_ text: String, allowed: [SecretConstant]) -> String {
        var result = text
        for constant in allowed {
            result = result.replacingOccurrences(of: constant.value, with: SecretConstantPlaceholders.token(for: constant.name))
        }
        return result
    }
}

/// Secret-constant redaction for agent-facing propose-send strings.
/// Uses `SecretConstantValueDetector` (the leak guard's secret path). Hits inside `{{mg:}}` tokens are kept.
public enum ProposalRedaction {
    public static func redact(_ text: String, constants: [SecretConstant], agentID: String) -> String {
        let hits = SecretConstantValueDetector.collect(in: text, constants: constants, agentID: agentID)
        guard !hits.isEmpty else { return text }
        let protected = SecretConstantPlaceholders.find(in: text)
        let applicable = hits.filter { hit in
            !protected.contains { token in
                hit.start < token.end && hit.end > token.start
            }
        }
        guard !applicable.isEmpty else { return text }
        var chars = Array(text)
        for hit in applicable.sorted(by: { $0.start > $1.start }) {
            let lo = max(0, min(hit.start, chars.count))
            let hi = max(lo, min(hit.end, chars.count))
            let marker = hit.actionValue.isEmpty ? "[redacted]" : hit.actionValue
            chars.replaceSubrange(lo..<hi, with: Array(marker))
        }
        return String(chars)
    }
}

public enum ProposalInstructionKind: String, Equatable, Sendable {
    case ask
    case rewrite
    case askAndRewrite = "ask_rewrite"
}

public enum ProposalAnswerShape: Equatable, Sendable {
    case yesNo
    case number
    case choices([String])
    case text

    public func dictionary() -> [String: Any] {
        switch self {
        case .yesNo:
            ["type": "yes_no"]
        case .number:
            ["type": "number"]
        case let .choices(options):
            ["type": "choices", "options": options]
        case .text:
            ["type": "text"]
        }
    }

    fileprivate var fallbackLabel: String {
        switch self {
        case .yesNo: "yes/no"
        case .number: "number"
        case let .choices(options): "one of: \(options.joined(separator: ", "))"
        case .text: "text"
        }
    }

    fileprivate func redacted(using redact: (String) -> String) -> Self {
        switch self {
        case let .choices(options): .choices(options.map(redact))
        default: self
        }
    }
}

public struct ProposalPassageInstruction: Equatable, Sendable, Identifiable {
    public var id: String
    public var kind: ProposalInstructionKind
    public var label: String
    public var answerShape: ProposalAnswerShape?

    public init(
        id: String,
        kind: ProposalInstructionKind,
        label: String,
        answerShape: ProposalAnswerShape? = nil
    ) {
        self.id = id
        self.kind = kind
        self.label = label
        self.answerShape = kind == .rewrite ? nil : answerShape
    }

    public func dictionary() -> [String: Any] {
        var out: [String: Any] = [
            "id": id,
            "kind": kind.rawValue,
            "label": label,
        ]
        if let answerShape {
            out["answerShape"] = answerShape.dictionary()
        }
        return out
    }

    fileprivate func redacted(using redact: (String) -> String) -> Self {
        ProposalPassageInstruction(
            id: id,
            kind: kind,
            label: redact(label),
            answerShape: answerShape?.redacted(using: redact)
        )
    }

    fileprivate var fallbackText: String {
        switch kind {
        case .ask:
            let answer = answerShape.map { " (answer: \($0.fallbackLabel))" } ?? ""
            return "Ask: \(label)\(answer)."
        case .rewrite:
            return "Rewrite: \(label)."
        case .askAndRewrite:
            let answer = answerShape.map { " (answer: \($0.fallbackLabel))" } ?? ""
            return "Ask and rewrite: \(label)\(answer)."
        }
    }
}

public enum ProposalPassageInstructions {
    public static func choices(from labels: [String]) -> [ProposalPassageInstruction] {
        labels.enumerated().map { index, label in
            let normalized = label.lowercased()
            let id = knownID(for: label) ?? "custom-\(index + 1)"
            if normalized.contains("accurate") && normalized.contains("up to date") {
                return ProposalPassageInstruction(id: id, kind: .ask, label: label, answerShape: .yesNo)
            }
            if normalized.contains("guess") || normalized.contains("verify") {
                return ProposalPassageInstruction(id: id, kind: .ask, label: label, answerShape: .text)
            }
            if normalized.contains("tone") {
                return ProposalPassageInstruction(
                    id: id,
                    kind: .ask,
                    label: label,
                    answerShape: .choices(["Right", "Too formal", "Too casual"])
                )
            }
            if normalized.contains("date") || normalized.contains("time") || normalized.contains("calendar") {
                return ProposalPassageInstruction(
                    id: id,
                    kind: .askAndRewrite,
                    label: label,
                    answerShape: .number
                )
            }
            if normalized.contains("short") || normalized.contains("rewrite") || normalized.contains("formal") {
                return ProposalPassageInstruction(id: id, kind: .rewrite, label: label)
            }
            return ProposalPassageInstruction(id: id, kind: .ask, label: label, answerShape: .text)
        }
    }

    private static func knownID(for label: String) -> String? {
        switch label {
        case "Check this is accurate and up to date": "accurate"
        case "This is a guess — verify before sending": "guess"
        case "Check tone is right for the recipient": "tone"
        case "Make this shorter": "shorter"
        case "Rewrite more formally": "formal"
        case "Check dates and times against my calendar": "dates"
        default: nil
        }
    }
}

public enum ProposalInstructionResultStatus: String, Equatable, Sendable {
    case pass
    case fail
}

public enum ProposalInstructionAnswer: Equatable, Sendable {
    case yesNo(Bool)
    case number(Double)
    case choice(String)
    case text(String)

    public func dictionary() -> [String: Any] {
        switch self {
        case let .yesNo(value):
            ["type": "yes_no", "value": value]
        case let .number(value):
            ["type": "number", "value": value]
        case let .choice(value):
            ["type": "choice", "value": value]
        case let .text(value):
            ["type": "text", "value": value]
        }
    }
}

public enum ProposalInstructionResultError: Error, Equatable, Sendable {
    case invalidResult
    case unknownReference
    case unknownInstruction
    case answerShapeMismatch
    case duplicateResult
}

public struct ProposalInstructionResult: Equatable, Sendable {
    public var referenceID: String
    public var instructionID: String
    public var status: ProposalInstructionResultStatus?
    public var answer: ProposalInstructionAnswer?

    public init(
        referenceID: String,
        instructionID: String,
        status: ProposalInstructionResultStatus? = nil,
        answer: ProposalInstructionAnswer? = nil
    ) {
        self.referenceID = referenceID
        self.instructionID = instructionID
        self.status = status
        self.answer = answer
    }

    public func dictionary() -> [String: Any] {
        var out: [String: Any] = [
            "referenceId": referenceID,
            "instructionId": instructionID,
        ]
        if let status { out["status"] = status.rawValue }
        if let answer { out["answer"] = answer.dictionary() }
        return out
    }

    public static func parseList(
        _ raw: Any?,
        references: [ProposalReferenceRecord]
    ) throws -> [Self] {
        guard let raw else { return [] }
        guard let rows = raw as? [Any] else {
            throw ProposalInstructionResultError.invalidResult
        }
        let referenceByID = Dictionary(uniqueKeysWithValues: references.map { ($0.id, $0) })
        var seen = Set<String>()
        return try rows.map { rawRow in
            guard let row = rawRow as? [String: Any],
                  let referenceID = row["referenceId"] as? String,
                  let instructionID = row["instructionId"] as? String,
                  let reference = referenceByID[referenceID]
            else {
                if let row = rawRow as? [String: Any],
                   row["referenceId"] is String,
                   row["instructionId"] is String
                {
                    throw ProposalInstructionResultError.unknownReference
                }
                throw ProposalInstructionResultError.invalidResult
            }
            guard let instruction = reference.instructions.first(where: { $0.id == instructionID }) else {
                throw ProposalInstructionResultError.unknownInstruction
            }
            let key = "\(referenceID)\u{1f}\(instructionID)"
            guard seen.insert(key).inserted else {
                throw ProposalInstructionResultError.duplicateResult
            }
            let status: ProposalInstructionResultStatus?
            if let rawStatus = row["status"] {
                guard let value = rawStatus as? String,
                      let parsed = ProposalInstructionResultStatus(rawValue: value)
                else {
                    throw ProposalInstructionResultError.invalidResult
                }
                status = parsed
            } else {
                status = nil
            }
            let answer = try parseAnswer(row["answer"], shape: instruction.answerShape)
            return ProposalInstructionResult(
                referenceID: referenceID,
                instructionID: instructionID,
                status: status,
                answer: answer
            )
        }
    }

    private static func parseAnswer(
        _ raw: Any?,
        shape: ProposalAnswerShape?
    ) throws -> ProposalInstructionAnswer? {
        guard let raw else { return nil }
        guard let shape,
              let object = raw as? [String: Any],
              let type = object["type"] as? String
        else {
            throw ProposalInstructionResultError.answerShapeMismatch
        }
        switch shape {
        case .yesNo:
            guard type == "yes_no", let value = object["value"] as? Bool else {
                throw ProposalInstructionResultError.answerShapeMismatch
            }
            return .yesNo(value)
        case .number:
            guard type == "number",
                  let value = object["value"] as? NSNumber,
                  CFGetTypeID(value) != CFBooleanGetTypeID()
            else {
                throw ProposalInstructionResultError.answerShapeMismatch
            }
            return .number(value.doubleValue)
        case let .choices(options):
            guard type == "choice",
                  let value = object["value"] as? String,
                  options.contains(value)
            else {
                throw ProposalInstructionResultError.answerShapeMismatch
            }
            return .choice(value)
        case .text:
            guard type == "text", let value = object["value"] as? String else {
                throw ProposalInstructionResultError.answerShapeMismatch
            }
            return .text(value)
        }
    }
}

public struct ProposalPin: Equatable, Sendable, Identifiable {
    public var id: String
    public var quote: String
    public var note: String
    public var instructions: [ProposalPassageInstruction]

    public init(
        id: String,
        quote: String,
        note: String = "",
        instructions: [ProposalPassageInstruction] = []
    ) {
        self.id = id
        self.quote = quote
        self.note = note
        self.instructions = instructions
    }
}

public struct ProposalReferenceRecord: Equatable, Sendable {
    public var id: String
    public var quote: String
    public var note: String?
    public var stale: Bool
    public var instructions: [ProposalPassageInstruction]
    public var instructionText: String

    public init(
        id: String,
        quote: String,
        note: String?,
        stale: Bool,
        instructions: [ProposalPassageInstruction] = [],
        instructionText: String = ""
    ) {
        self.id = id
        self.quote = quote
        self.note = note
        self.stale = stale
        self.instructions = instructions
        self.instructionText = instructionText
    }

    public func dictionary() -> [String: Any] {
        var out: [String: Any] = [
            "id": id,
            "quote": quote,
            "stale": stale,
        ]
        if let note { out["note"] = note }
        if !instructions.isEmpty {
            out["instructions"] = instructions.map { $0.dictionary() }
        }
        // Chip prose fallback only — never echo `note` as `Note: …`.
        if !instructionText.isEmpty {
            out["instructionText"] = instructionText
        }
        return out
    }
}

public enum ProposalPins {
    public static func anchor(
        _ pins: [ProposalPin],
        in body: String,
        redact: (String) -> String
    ) -> [ProposalReferenceRecord] {
        pins.map { pin in
            let trimmedNote = pin.note.trimmingCharacters(in: .whitespacesAndNewlines)
            let note = trimmedNote.isEmpty ? nil : redact(trimmedNote)
            let instructions = pin.instructions.map { $0.redacted(using: redact) }
            let instructionText = instructions.map(\.fallbackText).joined(separator: " ")
            let stale = pin.quote.isEmpty || !body.contains(pin.quote)
            return ProposalReferenceRecord(
                id: pin.id,
                quote: redact(pin.quote),
                note: note,
                stale: stale,
                instructions: instructions,
                instructionText: instructionText
            )
        }
    }
}

public enum ProposalNoteFuzzy {
    public static let defaultPresets: [String] = [
        "Check this is accurate and up to date",
        "This is a guess — verify before sending",
        "Check tone is right for the recipient",
        "Make this shorter",
        "Rewrite more formally",
        "Check dates and times against my calendar"
    ]

    /// 0 = no match. Empty query scores 1 so every preset stays listed.
    public static func score(query: String, text: String) -> Int {
        let folded = query.lowercased()
        let collapsed = folded.replacingOccurrences(
            of: #"\s+"#,
            with: "",
            options: .regularExpression
        )
        let haystack = Array(text.lowercased())
        if collapsed.isEmpty { return 1 }
        var hi = 0
        var score = 0
        var streak = 0
        let boundaries: Set<Character> = [" ", "-", ",", ".", "—", "'", "("]
        for character in collapsed {
            guard hi <= haystack.count else { return 0 }
            guard let relative = haystack[hi...].firstIndex(of: character) else { return 0 }
            if relative == hi, hi > 0 {
                streak += 2
            } else {
                streak = 0
            }
            let boundaryBonus: Int
            if relative == 0 || boundaries.contains(haystack[relative - 1]) {
                boundaryBonus = 3
            } else {
                boundaryBonus = 0
            }
            score += 2 + streak + boundaryBonus
            hi = relative + 1
        }
        return score
    }

    public static func suggestions(query: String, presets: [String], limit: Int = 6) -> [String] {
        presets
            .map { (text: $0, score: score(query: query, text: $0)) }
            .filter { $0.score > 0 }
            .sorted { lhs, rhs in
                if lhs.score != rhs.score { return lhs.score > rhs.score }
                return false
            }
            .prefix(limit)
            .map(\.text)
    }
}

public enum ProposalRevisePreset: String, CaseIterable, Sendable {
    case shorter = "Shorter"
    case warmer = "Warmer"
    case moreFormal = "More formal"
    case plainer = "Plainer"
    case friendlierClose = "Friendlier close"
    case changeRegister = "Change register…"
    case translate = "Translate…"

    public var phrase: String {
        switch self {
        case .shorter: "Make it shorter."
        case .warmer: "Make it warmer."
        case .moreFormal: "Make it more formal."
        case .plainer: "Use plainer words."
        case .friendlierClose: "Friendlier closing line."
        case .changeRegister: "Change the register (ask in the note)."
        case .translate: "Translate (language in the note)."
        }
    }

    public static func phrase(for label: String) -> String? {
        Self(rawValue: label)?.phrase
    }
}

public enum ProposalInstruction {
    public static func revise(
        presets: [String],
        note: String,
        pinCount: Int,
        hasUserEdits: Bool
    ) -> String {
        var phrases = ["Regenerate the whole draft."]
        for preset in presets {
            if let phrase = ProposalRevisePreset.phrase(for: preset) {
                phrases.append(phrase)
            }
        }
        let trimmed = note.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty {
            let sentence = ".!?".contains(trimmed.last!) ? trimmed : trimmed + "."
            phrases.append("Note from the user: \(sentence)")
        }
        if pinCount > 0 {
            let plural = pinCount == 1 ? "" : "s"
            phrases.append(
                "The user also pinned \(pinCount) passage\(plural) for your attention (references). Read them before you rewrite."
            )
        }
        if hasUserEdits {
            phrases.append(
                "The user also edited the draft by hand (userEdits). Keep those edits unless they conflict with the note."
            )
        }
        return phrases.joined(separator: " ")
    }

    public static func attention(pinCount: Int) -> String {
        let plural = pinCount == 1 ? "" : "s"
        return "The user pinned \(pinCount) passage\(plural) for your attention. Read them and respond. Do not change the draft unless the user asks."
    }
}

public struct ProposalReplyContext: Equatable, Sendable {
    public var casePath: String
    public var caseLabel: String
    public var shownEventIds: [String]
    public var referencedEventIds: [String]

    public init(
        casePath: String,
        caseLabel: String,
        shownEventIds: [String],
        referencedEventIds: [String]
    ) {
        self.casePath = casePath
        self.caseLabel = caseLabel
        self.shownEventIds = shownEventIds
        self.referencedEventIds = referencedEventIds
    }

    public func dictionary() -> [String: Any] {
        [
            "casePath": casePath,
            "caseLabel": caseLabel,
            "shownEventIds": shownEventIds,
            "referencedEventIds": referencedEventIds
        ]
    }
}

public struct ProposalRevisionRecord: Equatable, Sendable {
    public var presets: [String]
    public var note: String?
    public var instructionText: String

    public init(presets: [String], note: String?, instructionText: String) {
        self.presets = presets
        self.note = note
        self.instructionText = instructionText
    }

    public func dictionary() -> [String: Any] {
        var out: [String: Any] = [
            "scope": ["type": "draft"],
            "presets": presets,
            "instructionText": instructionText
        ]
        if let note { out["note"] = note }
        return out
    }
}

/// Agent-facing outcome. Secret values must already be redacted. Not a delivery record.
public struct ProposalAgentPayload: Equatable, Sendable {
    public static let reviseNextStepMessage =
        "Call propose_send with revises.proposalId set to this proposalId (same window). Do not open a new proposal."

    public var outcome: String
    public var proposalId: String?
    public var edited: Bool?
    public var changes: ProposalChanges?
    public var sentBody: String?
    public var currentBody: String?
    public var userEdits: ProposalChanges?
    public var references: [ProposalReferenceRecord]
    public var context: ProposalReplyContext?
    public var revision: ProposalRevisionRecord?
    public var instructionText: String?
    public var message: String?

    public init(
        outcome: String,
        proposalId: String? = nil,
        edited: Bool? = nil,
        changes: ProposalChanges? = nil,
        sentBody: String? = nil,
        currentBody: String? = nil,
        userEdits: ProposalChanges? = nil,
        references: [ProposalReferenceRecord] = [],
        context: ProposalReplyContext? = nil,
        revision: ProposalRevisionRecord? = nil,
        instructionText: String? = nil,
        message: String? = nil
    ) {
        self.outcome = outcome
        self.proposalId = proposalId
        self.edited = edited
        self.changes = changes
        self.sentBody = sentBody
        self.currentBody = currentBody
        self.userEdits = userEdits
        self.references = references
        self.context = context
        self.revision = revision
        self.instructionText = instructionText
        self.message = message
    }

    public func dictionary() -> [String: Any] {
        var out: [String: Any] = ["outcome": outcome]
        if let proposalId { out["proposalId"] = proposalId }
        if let edited { out["edited"] = edited }
        if let changes, !changes.isEmpty { out["changes"] = changes.dictionary() }
        if let sentBody { out["sentBody"] = sentBody }
        if let currentBody { out["currentBody"] = currentBody }
        if let userEdits, !userEdits.isEmpty { out["userEdits"] = userEdits.dictionary() }
        if !references.isEmpty { out["references"] = references.map { $0.dictionary() } }
        if let context { out["context"] = context.dictionary() }
        if let revision { out["revision"] = revision.dictionary() }
        if let instructionText { out["instructionText"] = instructionText }
        if let message { out["message"] = message }
        return out
    }
}

public enum ProposalPayloadBuilder {
    public static func changes(
        beforeTo: [String],
        afterTo: [String],
        beforeCc: [String],
        afterCc: [String],
        beforeBcc: [String],
        afterBcc: [String],
        beforeSubject: String,
        afterSubject: String,
        beforeBody: String,
        afterBody: String,
        constants: [SecretConstant],
        agentID: String
    ) -> ProposalChanges {
        let redact: (String) -> String = { ProposalRedaction.redact($0, constants: constants, agentID: agentID) }
        let bodyHunks = ProposalBodyDiff.hunks(before: beforeBody, after: afterBody).map {
            ProposalTextHunk(before: redact($0.before), after: redact($0.after))
        }
        return ProposalChanges(
            to: ProposalEnvelopeDiff.swap(before: beforeTo, after: afterTo, redact: redact),
            cc: ProposalEnvelopeDiff.swap(before: beforeCc, after: afterCc, redact: redact),
            bcc: ProposalEnvelopeDiff.swap(before: beforeBcc, after: afterBcc, redact: redact),
            subject: ProposalEnvelopeDiff.swap(before: beforeSubject, after: afterSubject, redact: redact),
            body: bodyHunks
        )
    }

    public static func send(
        proposalId: String,
        changes: ProposalChanges,
        sentBody: String?,
        references: [ProposalReferenceRecord],
        context: ProposalReplyContext?
    ) -> ProposalAgentPayload {
        if changes.isEmpty {
            return ProposalAgentPayload(
                outcome: "send",
                proposalId: proposalId,
                edited: false,
                references: references,
                context: context
            )
        }
        return ProposalAgentPayload(
            outcome: "send",
            proposalId: proposalId,
            edited: true,
            changes: changes,
            sentBody: sentBody,
            references: references,
            context: context
        )
    }

    public static func revise(
        proposalId: String,
        presets: [String],
        note: String,
        currentBody: String,
        userEdits: ProposalChanges,
        references: [ProposalReferenceRecord],
        context: ProposalReplyContext?,
        constants: [SecretConstant],
        agentID: String
    ) -> ProposalAgentPayload {
        let redact: (String) -> String = { ProposalRedaction.redact($0, constants: constants, agentID: agentID) }
        let redactedNote = redact(note.trimmingCharacters(in: .whitespacesAndNewlines))
        let instruction = ProposalInstruction.revise(
            presets: presets,
            note: redactedNote,
            pinCount: references.count,
            hasUserEdits: !userEdits.isEmpty
        )
        return ProposalAgentPayload(
            outcome: "revise_requested",
            proposalId: proposalId,
            currentBody: redact(currentBody),
            userEdits: userEdits.isEmpty ? nil : userEdits,
            references: references,
            context: context,
            revision: ProposalRevisionRecord(
                presets: presets,
                note: redactedNote.isEmpty ? nil : redactedNote,
                instructionText: instruction
            ),
            message: ProposalAgentPayload.reviseNextStepMessage
        )
    }

    public static func attention(
        proposalId: String,
        userEdits: ProposalChanges,
        references: [ProposalReferenceRecord],
        context: ProposalReplyContext?
    ) -> ProposalAgentPayload {
        ProposalAgentPayload(
            outcome: "attention_requested",
            proposalId: proposalId,
            userEdits: userEdits.isEmpty ? nil : userEdits,
            references: references,
            context: context,
            instructionText: ProposalInstruction.attention(pinCount: references.count),
            message: ProposalAgentPayload.reviseNextStepMessage
        )
    }
}

public enum ProposalRevisionApplyError: Error, Equatable, Sendable {
    case unknown
    case wrongAgent
    case notWaitingForRevision
    case expired
}
