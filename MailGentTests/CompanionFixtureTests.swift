import Foundation
import MailStore
import Testing
@testable import MailGent

struct CompanionFixtureTests {
    @Test func plantsMultipartHTMLForShowcaseMessages() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("MailGent-CompanionFixture-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }

        try CompanionFixture.plant(at: root)
        let store = MailStore(root: root)

        let boarding = try store.message(
            accountID: CompanionAccounts.personal,
            mailbox: "INBOX",
            id: "24"
        )
        #expect(boarding.subject.contains("EDI"))
        #expect(boarding.body.contains("Seat: 14A") || boarding.body.contains("14A"))
        #expect(boarding.htmlBody?.contains("Boarding pass") == true)
        #expect(boarding.internetMessageID.contains("@companion.mailgent.local"))

        let bank = try store.message(
            accountID: CompanionAccounts.personal,
            mailbox: "INBOX",
            id: "23"
        )
        #expect(bank.htmlBody?.contains("New login from Safari") == true)

        let newsletter = try store.message(
            accountID: CompanionAccounts.work,
            mailbox: "INBOX",
            id: "30"
        )
        #expect(newsletter.htmlBody?.contains("Engineering weekly") == true)

        // Short sent replies stay plain-only.
        let sent = try store.message(
            accountID: CompanionAccounts.work,
            mailbox: "Sent Messages",
            id: "17"
        )
        #expect(sent.htmlBody == nil)
        #expect(sent.body.contains("15:00 works"))

        // Edge cases stay plain stubs.
        let partial = try store.message(
            accountID: CompanionAccounts.personal,
            mailbox: "INBOX",
            id: "7"
        )
        #expect(partial.isPartial == true)
        #expect(partial.body == "has stub")
        #expect(partial.htmlBody == nil)
    }

    @Test func arrivalWaveEmitsHTML() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("MailGent-CompanionArrival-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }

        try CompanionFixture.plantArrival(at: root, wave: 0)
        let store = MailStore(root: root)
        let ci = try store.message(
            accountID: CompanionAccounts.work,
            mailbox: "INBOX",
            id: "w0-b"
        )
        #expect(ci.htmlBody?.contains("green on arm64") == true)
        #expect(ci.body.contains("release-smoke"))
    }
}
