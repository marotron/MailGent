import Testing
@testable import MailGent

struct MailAddressPartsTests {
    @Test func parseListKeepsBareAddressAfterNamedMailbox() {
        let list = MailAddressParts.parseList(
            "Melissa Cannon <Melissa.Cannon@johnshepherd.com>, Aleemah.Aziz@johnshepherd.com"
        )
        #expect(list.count == 2)
        #expect(list[0] == MailAddressParts(name: "Melissa Cannon", email: "Melissa.Cannon@johnshepherd.com"))
        #expect(list[1] == MailAddressParts(name: nil, email: "Aleemah.Aziz@johnshepherd.com"))
    }

    @Test func parseListKeepsQuotedNameContainingComma() {
        let list = MailAddressParts.parseList(
            "\"Cannon, Melissa\" <Melissa.Cannon@johnshepherd.com>, Aleemah.Aziz@johnshepherd.com"
        )
        #expect(list.count == 2)
        #expect(list[0] == MailAddressParts(name: "Cannon, Melissa", email: "Melissa.Cannon@johnshepherd.com"))
        #expect(list[1] == MailAddressParts(name: nil, email: "Aleemah.Aziz@johnshepherd.com"))
    }

    @Test func parseListSingleNamedMailbox() {
        let list = MailAddressParts.parseList("Lara Soars - White <lara.soarswhite@johnshepherd.com>")
        #expect(list == [
            MailAddressParts(name: "Lara Soars - White", email: "lara.soarswhite@johnshepherd.com"),
        ])
    }

    @Test func parseListEmpty() {
        #expect(MailAddressParts.parseList("").isEmpty)
        #expect(MailAddressParts.parseList("   ").isEmpty)
    }
}
