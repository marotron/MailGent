import Foundation
import MailStore
import Testing

struct OutboundLeakGuardTests {
    private func guardWith(
        enabled: Bool = true,
        scopes: Set<String> = ["work/INBOX"],
        builtIns: [BuiltInLeakClass: Bool]? = nil,
        rules: [CustomLeakRule] = [],
        subjectHitMode: LeakGuardHitMode = .redactSpans,
        bodyHitMode: LeakGuardHitMode = .redactSpans
    ) -> OutboundLeakGuard {
        OutboundLeakGuard(
            policy: OutboundLeakGuardPolicy(
                enabled: enabled,
                scopes: scopes,
                builtInClasses: builtIns,
                customRules: rules,
                subjectHitMode: subjectHitMode,
                bodyHitMode: bodyHitMode
            )
        )
    }

    @Test func masterOffPassthrough() {
        let guard_ = guardWith(enabled: false)
        let result = guard_.sanitize(
            text: "token=secret123",
            field: .body,
            accountID: "work",
            placement: "INBOX",
            fieldGranted: true
        )
        #expect(result.agentAccess == .granted)
        #expect(result.text == "token=secret123")
    }

    @Test func emptyAllowlistPassthrough() {
        let guard_ = guardWith(scopes: [])
        let result = guard_.sanitize(
            text: "token=secret123",
            field: .body,
            accountID: "work",
            placement: "INBOX",
            fieldGranted: true
        )
        #expect(result.agentAccess == .granted)
    }

    @Test func scopeOptInGatesScanning() {
        let guard_ = guardWith(scopes: ["work/Sent"])
        let skipped = guard_.sanitize(
            text: "token=secret123",
            field: .body,
            accountID: "work",
            placement: "INBOX",
            fieldGranted: true
        )
        #expect(skipped.agentAccess == .granted)

        let scanned = guard_.sanitize(
            text: "token=secret123",
            field: .body,
            accountID: "work",
            placement: "Sent",
            fieldGranted: true
        )
        #expect(scanned.agentAccess == .sanitized)
    }

    @Test func accountWideScopeMatchesPlacement() {
        let guard_ = guardWith(scopes: ["work/*"])
        let result = guard_.sanitize(
            text: "password=hunter2",
            field: .subject,
            accountID: "work",
            placement: "Archive",
            fieldGranted: true
        )
        #expect(result.agentAccess == .sanitized)
        #expect(result.text.contains("[REDACTED:passwordCtx]"))
    }

    @Test func grantDeniedFieldNotScanned() {
        let guard_ = guardWith()
        let result = guard_.sanitize(
            text: "token=secret123",
            field: .body,
            accountID: "work",
            placement: "INBOX",
            fieldGranted: false
        )
        #expect(result.access == .notGranted)
        #expect(result.reason == .grant)
        #expect(result.text.isEmpty)
    }

    @Test func builtInApiKeyRedact() {
        let guard_ = guardWith(builtIns: [.apiKeys: true])
        let result = guard_.sanitize(
            text: "Use sk-live-abcdefghijklmnop",
            field: .body,
            accountID: "work",
            placement: "INBOX",
            fieldGranted: true
        )
        #expect(result.agentAccess == .sanitized)
        #expect(result.text == "Use [REDACTED:apiKeys]")
        #expect(result.disclosedRules.contains("API keys"))
    }

    @Test func customLiteralRedact() {
        let rule = CustomLeakRule(
            label: "My name",
            kind: .literal,
            pattern: "Marotron",
            caseInsensitive: true,
            action: .redact,
            actionValue: "[REDACTED:name]"
        )
        let guard_ = guardWith(builtIns: [:], rules: [rule])
        let result = guard_.sanitize(
            text: "Hi Marotron — ping me",
            field: .body,
            accountID: "work",
            placement: "INBOX",
            fieldGranted: true
        )
        #expect(result.text == "Hi [REDACTED:name] — ping me")
        #expect(result.agentAccess == .sanitized)
    }

    @Test func customReplaceStealth() {
        let rule = CustomLeakRule(
            label: "My name",
            kind: .literal,
            pattern: "Marotron",
            action: .replace,
            actionValue: "John Smith",
            discloseToAgent: false
        )
        let guard_ = guardWith(builtIns: [:], rules: [rule])
        let result = guard_.sanitize(
            text: "From Marotron",
            field: .body,
            accountID: "work",
            placement: "INBOX",
            fieldGranted: true
        )
        #expect(result.text == "From John Smith")
        #expect(result.agentAccess == .granted)
        #expect(result.stealth)
        #expect(result.disclosedRules.isEmpty)
        #expect(result.allRules == ["My name"])
    }

    @Test func customReplaceDisclosed() {
        let rule = CustomLeakRule(
            label: "My name",
            kind: .literal,
            pattern: "Marotron",
            action: .replace,
            actionValue: "John Smith",
            discloseToAgent: true
        )
        let guard_ = guardWith(builtIns: [:], rules: [rule])
        let result = guard_.sanitize(
            text: "From Marotron",
            field: .body,
            accountID: "work",
            placement: "INBOX",
            fieldGranted: true
        )
        #expect(result.agentAccess == .sanitized)
        #expect(result.disclosedRules == ["My name"])
    }

    @Test func wildcardRuleMatches() {
        let rule = CustomLeakRule(
            label: "Address",
            kind: .wildcard,
            pattern: "*Evergreen Terrace*",
            caseInsensitive: true,
            action: .redact,
            actionValue: "[REDACTED:address]"
        )
        let guard_ = guardWith(builtIns: [:], rules: [rule])
        let result = guard_.sanitize(
            text: "742 Evergreen Terrace, Springfield",
            field: .body,
            accountID: "work",
            placement: "INBOX",
            fieldGranted: true
        )
        #expect(result.text.contains("[REDACTED:address]"))
    }

    @Test func overlapResolutionLongestSpanWins() {
        let short = CustomLeakRule(
            label: "Short",
            kind: .literal,
            pattern: "secret",
            action: .redact,
            actionValue: "[SHORT]"
        )
        let long = CustomLeakRule(
            label: "Long",
            kind: .literal,
            pattern: "token=secret123",
            action: .redact,
            actionValue: "[LONG]"
        )
        let guard_ = guardWith(builtIns: [:], rules: [short, long])
        let result = guard_.sanitize(
            text: "token=secret123",
            field: .body,
            accountID: "work",
            placement: "INBOX",
            fieldGranted: true
        )
        #expect(result.hitSpans.count == 1)
        #expect(result.hitSpans[0].label == "Long")
        #expect(result.text == "[LONG]")
    }

    @Test func blockWholeWithholdsField() {
        let guard_ = guardWith(bodyHitMode: .blockWhole)
        let result = guard_.sanitize(
            text: "password=hunter2 in thread",
            field: .body,
            accountID: "work",
            placement: "INBOX",
            fieldGranted: true
        )
        #expect(result.agentAccess == .withheldConfidential)
        #expect(result.reason == .leakGuard)
        #expect(result.text.isEmpty)
    }

    @Test func subjectAndBodyHitModesIndependent() {
        let guard_ = guardWith(subjectHitMode: .blockWhole, bodyHitMode: .redactSpans)
        let subject = guard_.sanitize(
            text: "password=hunter2",
            field: .subject,
            accountID: "work",
            placement: "INBOX",
            fieldGranted: true
        )
        #expect(subject.agentAccess == .withheldConfidential)

        let body = guard_.sanitize(
            text: "password=hunter2",
            field: .body,
            accountID: "work",
            placement: "INBOX",
            fieldGranted: true
        )
        #expect(body.agentAccess == .sanitized)
        #expect(body.text.contains("[REDACTED:passwordCtx]"))
    }

    @Test func invalidRegexAtRuntimeFailsOpen() {
        let rule = CustomLeakRule(
            label: "Bad regex",
            kind: .regex,
            pattern: "(unclosed",
            action: .redact,
            actionValue: "[X]"
        )
        let guard_ = guardWith(builtIns: [:], rules: [rule])
        let result = guard_.sanitize(
            text: "nothing sensitive",
            field: .body,
            accountID: "work",
            placement: "INBOX",
            fieldGranted: true
        )
        #expect(result.agentAccess == .granted)
    }

    @Test func validatePatternRejectsInvalidRegex() {
        #expect(CustomLeakRule.validatePattern(kind: .regex, pattern: "(bad") != nil)
        #expect(CustomLeakRule.validatePattern(kind: .regex, pattern: "ok") == nil)
        #expect(CustomLeakRule.validatePattern(kind: .literal, pattern: "x") == nil)
    }

    @Test func policyRoundTripsThroughJSON() throws {
        let policy = OutboundLeakGuardPolicy(
            enabled: true,
            scopes: ["work/INBOX", "personal/*"],
            customRules: [
                CustomLeakRule(label: "Test", kind: .literal, pattern: "x", action: .redact, actionValue: "[X]")
            ]
        )
        let data = try JSONEncoder().encode(policy)
        let decoded = try JSONDecoder().decode(OutboundLeakGuardPolicy.self, from: data)
        #expect(decoded == policy)
    }

    @Test func defaultBuiltInsMatchPlan() {
        let policy = OutboundLeakGuardPolicy.default
        #expect(policy.enabled == false)
        #expect(policy.builtInClasses[.apiKeys] == true)
        #expect(policy.builtInClasses[.jwt] == true)
        #expect(policy.builtInClasses[.passwordCtx] == true)
        #expect(policy.builtInClasses[.emails] == false)
    }
}
