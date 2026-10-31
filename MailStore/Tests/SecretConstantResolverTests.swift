import Foundation
import MailStore
import Testing

struct SecretConstantResolverTests {
    private func constant(
        name: String,
        value: String,
        updatedAt: Date = Date(timeIntervalSince1970: 1000)
    ) -> SecretConstant {
        SecretConstant(
            name: name,
            label: name,
            hint: .other,
            value: value,
            allowedAgentIDs: ["cursor"],
            multiline: false,
            updatedAt: updatedAt
        )
    }

    @Test func resolveSubstitutesValuesAndSpans() throws {
        let catalog = [
            "phone_mobile": constant(name: "phone_mobile", value: "+1-555-0100"),
            "home_address": constant(name: "home_address", value: "1 Main St"),
        ]
        let body = "Call [[mg:phone_mobile]] at [[mg:home_address]]."
        let result = try SecretConstantResolver.resolve(body: body, catalog: catalog)

        #expect(result.resolved == "Call +1-555-0100 at 1 Main St.")
        #expect(result.spans.count == 2)
        #expect(result.spans[0].name == "phone_mobile")
        #expect(result.spans[0].start == 5)
        #expect(result.spans[0].end == 16)
        #expect(result.spans[0].updatedSinceDraft == false)
        #expect(result.spans[1].name == "home_address")
        #expect(result.spans[1].start == 20)
        #expect(result.spans[1].end == 29)
    }

    @Test func resolveFailsClosedOnMissingNames() {
        let catalog = ["phone_mobile": constant(name: "phone_mobile", value: "x")]
        let body = "[[mg:phone_mobile]] and [[mg:missing_one]] plus [[mg:also_gone]]"
        #expect(throws: SecretConstantResolveError.missingNames(["missing_one", "also_gone"])) {
            try SecretConstantResolver.resolve(body: body, catalog: catalog)
        }
    }

    @Test func resolveMarksUpdatedSinceDraft() throws {
        let draftedAt = Date(timeIntervalSince1970: 500)
        let catalog = [
            "phone_mobile": constant(
                name: "phone_mobile",
                value: "new",
                updatedAt: Date(timeIntervalSince1970: 900)
            ),
            "home_address": constant(
                name: "home_address",
                value: "same",
                updatedAt: Date(timeIntervalSince1970: 100)
            ),
        ]
        let body = "[[mg:phone_mobile]] / [[mg:home_address]]"
        let result = try SecretConstantResolver.resolve(
            body: body,
            catalog: catalog,
            draftedAt: draftedAt
        )
        #expect(result.spans[0].updatedSinceDraft == true)
        #expect(result.spans[1].updatedSinceDraft == false)
    }

    @Test func resolveLeavesPlainBodyUnchanged() throws {
        let result = try SecretConstantResolver.resolve(body: "hello", catalog: [:])
        #expect(result.resolved == "hello")
        #expect(result.spans.isEmpty)
    }

    @Test func resolvePreservesMultilineValues() throws {
        let catalog = [
            "home_address": constant(name: "home_address", value: "1 Main\nApt 2"),
        ]
        let result = try SecretConstantResolver.resolve(
            body: "Addr: [[mg:home_address]]",
            catalog: catalog
        )
        #expect(result.resolved == "Addr: 1 Main\nApt 2")
    }
}
