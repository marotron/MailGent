import Foundation

/// Literal value hits for stored secret constants (leak guard outbound path).
enum SecretConstantValueDetector {
    static func collect(
        in text: String,
        constants: [SecretConstant],
        agentID: String?
    ) -> [LeakHitSpan] {
        var hits: [LeakHitSpan] = []
        for constant in constants {
            let value = constant.value
            guard !value.isEmpty else { continue }
            let allowlisted = agentID.map { constant.allowedAgentIDs.contains($0) } ?? false
            let marker = allowlisted
                ? "[redacted:\(constant.name)]"
                : "[redacted]"
            let spans = SpanFinder.literalSpans(in: text, needle: value, caseInsensitive: false)
            for span in spans {
                hits.append(
                    LeakHitSpan(
                        start: span.start,
                        end: span.end,
                        label: constant.name,
                        source: "secretConstant:\(constant.name)",
                        action: .redact,
                        actionValue: marker,
                        discloseToAgent: true
                    )
                )
            }
        }
        return hits
    }

    static func isSecretConstantSource(_ source: String) -> Bool {
        source.hasPrefix("secretConstant:")
    }
}
