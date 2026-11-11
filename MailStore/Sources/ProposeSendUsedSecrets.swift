import Foundation

/// One secret shown under the propose-send body as `[[mg:name]] → value`.
public struct ProposeSendUsedSecretSummary: Equatable, Identifiable, Sendable {
    public var name: String
    public var value: String
    public var updated: Bool

    public var id: String { name }

    public init(name: String, value: String, updated: Bool) {
        self.name = name
        self.value = value
        self.updated = updated
    }
}

/// Ordered unique secrets for the confirm strip. Missing tokens are not listed —
/// only successful resolve spans count as “replaced for send.”
public enum ProposeSendUsedSecrets {
    public static func summaries(
        body: String,
        spans: [SecretConstantResolveSpan]
    ) -> [ProposeSendUsedSecretSummary] {
        var order: [String] = []
        var byName: [String: ProposeSendUsedSecretSummary] = [:]
        let chars = Array(body)
        for span in spans.sorted(by: { $0.start < $1.start }) {
            let start = max(0, min(span.start, chars.count))
            let end = max(start, min(span.end, chars.count))
            let value = String(chars[start..<end])
            if var existing = byName[span.name] {
                existing.updated = existing.updated || span.updatedSinceDraft
                if existing.value.isEmpty, !value.isEmpty {
                    existing.value = value
                }
                byName[span.name] = existing
            } else {
                order.append(span.name)
                byName[span.name] = ProposeSendUsedSecretSummary(
                    name: span.name,
                    value: value,
                    updated: span.updatedSinceDraft
                )
            }
        }
        return order.compactMap { byName[$0] }
    }
}
