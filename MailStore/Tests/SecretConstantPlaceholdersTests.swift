import Foundation
import MailStore
import Testing

struct SecretConstantPlaceholdersTests {
    @Test func validNames() {
        #expect(SecretConstantPlaceholders.isValidName("phone_mobile"))
        #expect(SecretConstantPlaceholders.isValidName("a"))
        #expect(SecretConstantPlaceholders.isValidName("tax_id_last4"))
        #expect(!SecretConstantPlaceholders.isValidName(""))
        #expect(!SecretConstantPlaceholders.isValidName("Phone"))
        #expect(!SecretConstantPlaceholders.isValidName("1phone"))
        #expect(!SecretConstantPlaceholders.isValidName("phone-mobile"))
        #expect(!SecretConstantPlaceholders.isValidName("phone.mobile"))
    }

    @Test func tokenForName() {
        #expect(SecretConstantPlaceholders.token(for: "phone_mobile") == "[[mg:phone_mobile]]")
    }

    @Test func findMatchesValidTokens() {
        let body = "Call [[mg:phone_mobile]] or [[mg:home_address]]."
        let matches = SecretConstantPlaceholders.find(in: body)
        #expect(matches.map(\.name) == ["phone_mobile", "home_address"])
        #expect(matches[0].start == 5)
        #expect(matches[0].end == 24)
    }

    @Test func findIgnoresInvalidNames() {
        let body = "Bad [[mg:Phone]] and [[mg:1x]] and good [[mg:ok]]."
        let matches = SecretConstantPlaceholders.find(in: body)
        #expect(matches.map(\.name) == ["ok"])
    }

    @Test func uniqueNamesPreservesFirstSeenOrder() {
        let body = "[[mg:b]] then [[mg:a]] then [[mg:b]] again"
        #expect(SecretConstantPlaceholders.uniqueNames(in: body) == ["b", "a"])
    }

    @Test func findEmptyWhenNone() {
        #expect(SecretConstantPlaceholders.find(in: "plain text").isEmpty)
        #expect(SecretConstantPlaceholders.uniqueNames(in: "plain").isEmpty)
    }
}
