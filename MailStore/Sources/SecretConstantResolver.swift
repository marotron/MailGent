import Foundation

public enum SecretConstantResolveError: Error, Equatable, Sendable {
    case missingNames([String])
}

public struct SecretConstantResolveSpan: Equatable, Sendable {
    public let name: String
    public let start: Int
    public let end: Int
    public let updatedSinceDraft: Bool

    public init(name: String, start: Int, end: Int, updatedSinceDraft: Bool) {
        self.name = name
        self.start = start
        self.end = end
        self.updatedSinceDraft = updatedSinceDraft
    }
}

public struct SecretConstantResolveResult: Equatable, Sendable {
    public let resolved: String
    public let spans: [SecretConstantResolveSpan]

    public init(resolved: String, spans: [SecretConstantResolveSpan]) {
        self.resolved = resolved
        self.spans = spans
    }
}

/// Human-path resolve only (confirm UI / Apple Mail handoff). Never apply to MCP tool returns.
public enum SecretConstantResolver {
    public static func resolve(
        body: String,
        catalog: [String: SecretConstant],
        draftedAt: Date? = nil
    ) throws -> SecretConstantResolveResult {
        let matches = SecretConstantPlaceholders.find(in: body)
        guard !matches.isEmpty else {
            return SecretConstantResolveResult(resolved: body, spans: [])
        }

        var missing: [String] = []
        var seenMissing = Set<String>()
        for match in matches {
            if catalog[match.name] == nil, seenMissing.insert(match.name).inserted {
                missing.append(match.name)
            }
        }
        if !missing.isEmpty {
            throw SecretConstantResolveError.missingNames(missing)
        }

        var resolved = ""
        var spans: [SecretConstantResolveSpan] = []
        var cursor = 0
        let chars = Array(body)

        for match in matches {
            let constant = catalog[match.name]!
            if cursor < match.start {
                resolved.append(contentsOf: chars[cursor..<match.start])
            }
            let valueStart = resolved.count
            resolved.append(constant.value)
            let valueEnd = resolved.count
            let updated: Bool
            if let draftedAt {
                updated = constant.updatedAt > draftedAt
            } else {
                updated = false
            }
            spans.append(
                SecretConstantResolveSpan(
                    name: match.name,
                    start: valueStart,
                    end: valueEnd,
                    updatedSinceDraft: updated
                )
            )
            cursor = match.end
        }
        if cursor < chars.count {
            resolved.append(contentsOf: chars[cursor...])
        }

        return SecretConstantResolveResult(resolved: resolved, spans: spans)
    }
}
