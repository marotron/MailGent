import Foundation
import MailStore
import Testing

struct SecretConstantsCatalogTests {
    private func make(
        name: String = "phone_mobile",
        label: String = "Mobile",
        agents: [String] = ["cursor"],
        value: String = "+1-555"
    ) -> SecretConstant {
        SecretConstant(
            name: name,
            label: label,
            hint: .phone,
            value: value,
            allowedAgentIDs: agents,
            multiline: false,
            updatedAt: Date(timeIntervalSince1970: 1)
        )
    }

    @Test func upsertInsertsAndUpdates() throws {
        var catalog = SecretConstantsCatalog()
        try catalog.upsert(make())
        #expect(catalog.constants.count == 1)
        #expect(catalog.constants[0].label == "Mobile")

        try catalog.upsert(make(label: "Cell", value: "+1-999"))
        #expect(catalog.constants.count == 1)
        #expect(catalog.constants[0].label == "Cell")
        #expect(catalog.constants[0].value == "+1-999")
    }

    @Test func upsertRejectsInvalidName() {
        var catalog = SecretConstantsCatalog()
        #expect(throws: SecretConstantsCatalogError.invalidName("Phone")) {
            try catalog.upsert(make(name: "Phone"))
        }
    }

    @Test func normalizeName() {
        #expect(SecretConstantsCatalog.normalizeName("phone_mobile") == "phone_mobile")
        #expect(SecretConstantsCatalog.normalizeName("  phone_mobile  ") == "phone_mobile")
        #expect(SecretConstantsCatalog.normalizeName("Phone") == nil)
        #expect(SecretConstantsCatalog.normalizeName("") == nil)
    }

    @Test func deleteRemovesConstant() throws {
        var catalog = SecretConstantsCatalog()
        try catalog.upsert(make())
        catalog.delete(name: "phone_mobile")
        #expect(catalog.constants.isEmpty)
    }

    @Test func allowlistFilter() throws {
        var catalog = SecretConstantsCatalog()
        try catalog.upsert(make(name: "phone_mobile", agents: ["cursor"]))
        try catalog.upsert(make(name: "home_address", agents: ["grok", "cursor"]))
        try catalog.upsert(make(name: "tax_id_last4", agents: []))

        let forCursor = catalog.allowed(forAgentID: "cursor")
        #expect(forCursor.map(\.name) == ["phone_mobile", "home_address"])
        #expect(catalog.allowed(forAgentID: "grok").map(\.name) == ["home_address"])
        #expect(catalog.allowed(forAgentID: "other").isEmpty)
    }

    @Test func validateInsertAllowsAllowlistedNames() throws {
        var catalog = SecretConstantsCatalog()
        try catalog.upsert(make(name: "phone_mobile", agents: ["cursor"]))
        try catalog.upsert(make(name: "home_address", agents: ["cursor"]))
        try catalog.validateInsert(names: ["phone_mobile", "home_address"], agentID: "cursor")
    }

    @Test func validateInsertRejectsNonAllowlisted() throws {
        var catalog = SecretConstantsCatalog()
        try catalog.upsert(make(name: "phone_mobile", agents: ["cursor"]))
        try catalog.upsert(make(name: "home_address", agents: ["grok"]))
        #expect(
            throws: SecretConstantsCatalogError.notAllowlisted(
                names: ["home_address", "missing"],
                agentID: "cursor"
            )
        ) {
            try catalog.validateInsert(
                names: ["phone_mobile", "home_address", "missing"],
                agentID: "cursor"
            )
        }
    }

    @Test func lookupByName() throws {
        var catalog = SecretConstantsCatalog()
        try catalog.upsert(make())
        #expect(catalog["phone_mobile"]?.label == "Mobile")
        #expect(catalog["missing"] == nil)
        #expect(catalog.dictionary["phone_mobile"]?.value == "+1-555")
    }
}
