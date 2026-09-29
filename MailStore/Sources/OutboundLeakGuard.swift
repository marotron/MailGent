import Foundation

public enum LeakGuardScanField: Sendable {
    case subject
    case body
}

public struct OutboundLeakGuard: Sendable {
    public var policy: OutboundLeakGuardPolicy

    public init(policy: OutboundLeakGuardPolicy = .default) {
        self.policy = policy
    }

    public func isScopeProtected(accountID: String, placement: String) -> Bool {
        policy.isScopeProtected(accountID: accountID, placement: placement)
    }

    public func sanitize(
        text: String,
        field: LeakGuardScanField,
        accountID: String,
        placement: String,
        fieldGranted: Bool
    ) -> SanitizedField {
        guard fieldGranted else {
            return .notGranted(original: text)
        }
        guard policy.enabled, isScopeProtected(accountID: accountID, placement: placement) else {
            return .granted(text)
        }
        let hits = resolveOverlaps(collectHits(in: text))
        let hitMode = field == .subject ? policy.subjectHitMode : policy.bodyHitMode
        return applyHits(original: text, hits: hits, hitMode: hitMode)
    }

    func collectHits(in text: String) -> [LeakHitSpan] {
        var hits = BuiltInHeuristicDetector.collect(in: text, enabledClasses: policy.builtInClasses)
        hits.append(contentsOf: CustomRuleDetector.collect(in: text, rules: policy.customRules))
        return hits
    }

    func resolveOverlaps(_ hits: [LeakHitSpan]) -> [LeakHitSpan] {
        let sorted = hits.sorted {
            if $0.length != $1.length { return $0.length > $1.length }
            return $0.start < $1.start
        }
        var kept: [LeakHitSpan] = []
        for hit in sorted {
            let overlaps = kept.contains { existing in
                !(hit.end <= existing.start || hit.start >= existing.end)
            }
            if !overlaps { kept.append(hit) }
        }
        return kept.sorted { $0.start < $1.start }
    }

    func applyHits(
        original: String,
        hits: [LeakHitSpan],
        hitMode: LeakGuardHitMode
    ) -> SanitizedField {
        guard !hits.isEmpty else {
            return .granted(original)
        }
        if hitMode == .blockWhole {
            let labels = Array(Set(hits.map(\.label))).sorted()
            return SanitizedField(
                text: "",
                access: .withheldConfidential,
                agentAccess: .withheldConfidential,
                reason: .leakGuard,
                disclosedRules: labels,
                allRules: labels,
                original: original,
                hitSpans: hits,
                stealth: false
            )
        }
        var out = original
        var allRules = Set<String>()
        var disclosedRules = Set<String>()
        for hit in hits.sorted(by: { $0.start > $1.start }) {
            let replacement = hit.action == .replace
                ? hit.actionValue
                : (hit.actionValue.isEmpty ? "[REDACTED:\(hit.label)]" : hit.actionValue)
            let start = out.index(out.startIndex, offsetBy: hit.start)
            let end = out.index(out.startIndex, offsetBy: hit.end)
            out.replaceSubrange(start..<end, with: replacement)
            allRules.insert(hit.label)
            if hit.discloseToAgent {
                disclosedRules.insert(hit.label)
            }
        }
        let disclosed = disclosedRules.sorted()
        let all = allRules.sorted()
        let agentAccess: FieldAccess = disclosed.isEmpty ? .granted : .sanitized
        let reason: FieldAccessReason = agentAccess == .sanitized ? .leakGuard : .grant
        return SanitizedField(
            text: out,
            access: .sanitized,
            agentAccess: agentAccess,
            reason: reason,
            disclosedRules: disclosed,
            allRules: all,
            original: original,
            hitSpans: hits,
            stealth: agentAccess == .granted
        )
    }
}
