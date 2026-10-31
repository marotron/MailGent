import Foundation
import MailStore
import Testing

struct SecretConstantValueDetectorTests {
    private func policyOn() -> OutboundLeakGuardPolicy {
        var policy = OutboundLeakGuardPolicy.default
        policy.enabled = true
        policy.scopes = [
            OutboundLeakGuardPolicy.scopeKey(accountID: "work", placement: "INBOX"),
        ]
        policy.builtInClasses = Dictionary(
            uniqueKeysWithValues: BuiltInLeakClass.allCases.map { ($0, false) }
        )
        return policy
    }

    private func constant(
        name: String,
        value: String,
        agents: [String]
    ) -> SecretConstant {
        SecretConstant(
            name: name,
            label: name,
            hint: .other,
            value: value,
            allowedAgentIDs: agents,
            multiline: false,
            updatedAt: Date(timeIntervalSince1970: 1)
        )
    }

    @Test func namedMarkerForAllowlistedAgent() {
        let constants = [
            constant(name: "phone_mobile", value: "+1-555-0100", agents: ["cursor"]),
        ]
        let guard_ = OutboundLeakGuard(policy: policyOn(), secretConstants: constants)
        let result = guard_.sanitize(
            text: "Call +1-555-0100 please",
            field: .body,
            accountID: "work",
            placement: "INBOX",
            fieldGranted: true,
            agentID: "cursor"
        )
        #expect(result.text == "Call [redacted:phone_mobile] please")
        #expect(result.reason == .secretConstant)
        #expect(result.agentAccess == .sanitized)
        #expect(result.disclosedRules.contains("phone_mobile"))
    }

    @Test func genericMarkerWhenNotAllowlisted() {
        let constants = [
            constant(name: "phone_mobile", value: "+1-555-0100", agents: ["cursor"]),
        ]
        let guard_ = OutboundLeakGuard(policy: policyOn(), secretConstants: constants)
        let result = guard_.sanitize(
            text: "Call +1-555-0100 please",
            field: .body,
            accountID: "work",
            placement: "INBOX",
            fieldGranted: true,
            agentID: "grok"
        )
        #expect(result.text == "Call [redacted] please")
        #expect(result.reason == .secretConstant)
    }

    @Test func genericMarkerWhenAgentUnknown() {
        let constants = [
            constant(name: "phone_mobile", value: "+1-555-0100", agents: ["cursor"]),
        ]
        let guard_ = OutboundLeakGuard(policy: policyOn(), secretConstants: constants)
        let result = guard_.sanitize(
            text: "Call +1-555-0100 please",
            field: .body,
            accountID: "work",
            placement: "INBOX",
            fieldGranted: true
        )
        #expect(result.text == "Call [redacted] please")
    }

    @Test func skipsEmptyValues() {
        let constants = [
            constant(name: "empty", value: "", agents: ["cursor"]),
        ]
        let guard_ = OutboundLeakGuard(policy: policyOn(), secretConstants: constants)
        let result = guard_.sanitize(
            text: "nothing secret here",
            field: .body,
            accountID: "work",
            placement: "INBOX",
            fieldGranted: true,
            agentID: "cursor"
        )
        #expect(result.agentAccess == .granted)
        #expect(result.text == "nothing secret here")
    }

    @Test func multilineValueLiteral() {
        let constants = [
            constant(name: "home_address", value: "1 Main\nApt 2", agents: ["cursor"]),
        ]
        let guard_ = OutboundLeakGuard(policy: policyOn(), secretConstants: constants)
        let result = guard_.sanitize(
            text: "Addr:\n1 Main\nApt 2\nThanks",
            field: .body,
            accountID: "work",
            placement: "INBOX",
            fieldGranted: true,
            agentID: "cursor"
        )
        #expect(result.text == "Addr:\n[redacted:home_address]\nThanks")
    }
}
