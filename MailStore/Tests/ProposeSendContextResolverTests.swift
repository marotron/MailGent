import Foundation
import MailStore
import Testing

@Suite struct ProposeSendContextResolverTests {
    @Test func sortsByAtThenAgentOrderAndAppendsDraft() async throws {
        let context = try SendProposalContext.parse([
            "casePath": "cases/acme",
            "events": [
                event(id: "e2", at: "2026-10-22T10:00:00Z", path: "b.md", summary: "second"),
                event(id: "e1", at: "2026-10-21T10:00:00Z", path: "a.md", summary: "first"),
                event(id: "e3", at: "2026-10-21T10:00:00Z", path: "c.md", summary: "same-time-later")
            ]
        ])
        let vault = FakeVault(files: [
            "cases/acme/a.md": "A",
            "cases/acme/b.md": "B",
            "cases/acme/c.md": "C"
        ])
        let resolver = ProposeSendContextResolver(mail: FakeMail(), vault: vault)
        let proposal = SendProposal(
            agentName: "Cursor",
            to: ["a@b.c"],
            subject: "Thanks Joanna",
            body: "Draft body"
        )
        let resolved = await resolver.resolve(context: context, proposal: proposal)
        #expect(resolved.items.map(\.id) == ["e1", "e3", "e2", "draft"])
        #expect(resolved.items.last?.isDraft == true)
        #expect(resolved.items.last?.summary == "Thanks Joanna")
        #expect(resolved.items.last?.detail == "Draft body")
        #expect(resolved.caseLabel == "acme")
    }

    @Test func softFailsMissingMailAndVault() async throws {
        let context = try SendProposalContext.parse([
            "casePath": "cases/acme",
            "events": [
                [
                    "id": "m1",
                    "kind": "mail",
                    "scope": "shared",
                    "ownership": "them",
                    "party": ["name": "Jo"],
                    "at": "2026-10-21T09:12:00Z",
                    "summary": "mail miss",
                    "source": [
                        "mail": ["accountID": "a", "placement": "INBOX", "id": "missing"]
                    ]
                ],
                event(id: "v1", at: "2026-10-20T11:40:00Z", path: "gone.md", summary: "vault miss")
            ]
        ])
        let resolver = ProposeSendContextResolver(mail: FakeMail(), vault: FakeVault(files: [:]))
        let proposal = SendProposal(agentName: "Cursor", to: ["a@b.c"], subject: "S", body: "B")
        let resolved = await resolver.resolve(context: context, proposal: proposal)
        let mail = resolved.items.first { $0.id == "m1" }
        let vault = resolved.items.first { $0.id == "v1" }
        #expect(mail?.unavailableReason == "Mail unavailable")
        #expect(vault?.unavailableReason == "Vault file unavailable")
        #expect(mail?.summary == "mail miss")
    }

    @Test func fillsMailDetailWhenFetchSucceeds() async throws {
        let context = try SendProposalContext.parse([
            "casePath": "cases/acme",
            "events": [
                [
                    "id": "m1",
                    "kind": "mail",
                    "scope": "shared",
                    "ownership": "them",
                    "party": ["name": "Jo", "initials": "JC"],
                    "at": "2026-10-21T09:12:00Z",
                    "summary": "Thanks",
                    "source": [
                        "mail": ["accountID": "a", "placement": "INBOX", "id": "1"]
                    ]
                ]
            ]
        ])
        let mail = FakeMail(content: [
            "a/INBOX/1": ProposeSendMailContent(
                subject: "Re: chat",
                from: "Jo <jo@x.com>",
                body: "Hello",
                internetMessageID: "<m1@x>"
            )
        ])
        let resolver = ProposeSendContextResolver(mail: mail, vault: FakeVault(files: [:]))
        let proposal = SendProposal(agentName: "Cursor", to: ["a@b.c"], subject: "S", body: "B")
        let resolved = await resolver.resolve(context: context, proposal: proposal)
        let item = resolved.items.first { $0.id == "m1" }
        #expect(item?.from == "Jo <jo@x.com>")
        #expect(item?.subject == "Re: chat")
        #expect(item?.detail == "Hello")
        #expect(item?.unavailableReason == nil)
        if case let .mail(_, _, id, messageID)? = item?.original {
            #expect(id == "1")
            #expect(messageID == "<m1@x>")
        } else {
            Issue.record("expected mail original")
        }
    }

    @Test func personalVaultReaderRejectsEscape() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("MailGent-vault-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let outside = root.deletingLastPathComponent().appendingPathComponent("outside.txt")
        try "secret".write(to: outside, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: outside) }

        #expect(PersonalVaultFileReader.resolvedFileURL(root: root, relativePath: "../outside.txt") == nil)
        let reader = PersonalVaultFileReader(rootURL: root)
        #expect(reader.readVaultFile(relativePath: "../outside.txt") == nil)
    }

    @Test func personalVaultReaderReadsUnderRoot() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("MailGent-vault-\(UUID().uuidString)", isDirectory: true)
        let caseDir = root.appendingPathComponent("cases/acme", isDirectory: true)
        try FileManager.default.createDirectory(at: caseDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let file = caseDir.appendingPathComponent("LOG.md")
        try "# prep\nhello".write(to: file, atomically: true, encoding: .utf8)

        let reader = PersonalVaultFileReader(rootURL: root)
        #expect(reader.readVaultFile(relativePath: "cases/acme/LOG.md") == "# prep\nhello")
    }
}

private func event(
    id: String,
    at: String,
    path: String,
    summary: String
) -> [String: Any] {
    [
        "id": id,
        "kind": "note",
        "scope": "private",
        "ownership": "you",
        "at": at,
        "summary": summary,
        "source": ["vault": ["path": path]]
    ]
}

private struct FakeMail: ProposeSendMailFetching {
    var content: [String: ProposeSendMailContent] = [:]

    func fetchMail(accountID: String, placement: String, id: String) async -> ProposeSendMailContent? {
        content["\(accountID)/\(placement)/\(id)"]
    }
}

private struct FakeVault: ProposeSendVaultReading {
    var files: [String: String]

    func readVaultFile(relativePath: String) -> String? {
        files[relativePath]
    }
}
