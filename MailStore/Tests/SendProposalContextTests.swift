import Foundation
import MailStore
import Testing

@Suite struct SendProposalContextTests {
    @Test func parsesValidContext() throws {
        let raw: [String: Any] = [
            "casePath": "cases/jobs/acme-staff-engineer",
            "caseLabel": "Acme · Staff Engineer",
            "events": [
                [
                    "id": "e1",
                    "kind": "phone",
                    "scope": "private",
                    "ownership": "you",
                    "at": "2026-10-20T11:40:00Z",
                    "summary": "Prep notes",
                    "source": ["vault": ["path": "LOG.md", "anchor": "2026-10-20-prep"]]
                ],
                [
                    "id": "e2",
                    "kind": "mail",
                    "scope": "shared",
                    "ownership": "them",
                    "party": ["name": "Joanna Chen", "initials": "JC"],
                    "at": "2026-10-21T09:12:00Z",
                    "summary": "Thanks for chatting",
                    "source": [
                        "mail": [
                            "accountID": "acct-1",
                            "placement": "INBOX",
                            "id": "msg-1"
                        ]
                    ]
                ]
            ],
            "links": [
                ["from": "e2", "to": "e1", "rel": "reply-to", "label": "Reply"]
            ]
        ]

        let context = try SendProposalContext.parse(raw)
        #expect(context.casePath == "cases/jobs/acme-staff-engineer")
        #expect(context.caseLabel == "Acme · Staff Engineer")
        #expect(context.events.count == 2)
        #expect(context.events[0].id == "e1")
        #expect(context.events[0].kind == .phone)
        #expect(context.events[0].scope == .private)
        #expect(context.events[0].ownership == .you)
        #expect(context.events[0].source == .vault(path: "LOG.md", anchor: "2026-10-20-prep"))
        #expect(context.events[1].party?.name == "Joanna Chen")
        #expect(context.events[1].party?.initials == "JC")
        #expect(
            context.events[1].source
                == .mail(accountID: "acct-1", placement: "INBOX", id: "msg-1")
        )
        #expect(context.links.count == 1)
        #expect(context.links[0].from == "e2")
        #expect(context.links[0].to == "e1")
        #expect(context.links[0].rel == "reply-to")
        #expect(context.links[0].label == "Reply")
    }

    @Test func rejectsPathEscape() {
        let raw: [String: Any] = [
            "casePath": "../secrets",
            "events": [
                [
                    "id": "e1",
                    "kind": "note",
                    "scope": "private",
                    "ownership": "you",
                    "at": "2026-10-20T11:40:00Z",
                    "summary": "x",
                    "source": ["vault": ["path": "LOG.md"]]
                ]
            ]
        ]
        #expect(throws: SendProposalContextError.self) {
            try SendProposalContext.parse(raw)
        }
    }

    @Test func rejectsAbsoluteCasePath() {
        let raw: [String: Any] = [
            "casePath": "/Users/me/Personal/cases/x",
            "events": [
                [
                    "id": "e1",
                    "kind": "note",
                    "scope": "private",
                    "ownership": "you",
                    "at": "2026-10-20T11:40:00Z",
                    "summary": "x",
                    "source": ["vault": ["path": "LOG.md"]]
                ]
            ]
        ]
        #expect(throws: SendProposalContextError.self) {
            try SendProposalContext.parse(raw)
        }
    }

    @Test func rejectsMoreThanFortyEvents() {
        var events: [[String: Any]] = []
        for i in 0..<41 {
            events.append([
                "id": "e\(i)",
                "kind": "note",
                "scope": "private",
                "ownership": "you",
                "at": "2026-10-20T11:40:00Z",
                "summary": "x",
                "source": ["vault": ["path": "n\(i).md"]]
            ])
        }
        let raw: [String: Any] = [
            "casePath": "cases/x",
            "events": events
        ]
        #expect(throws: SendProposalContextError.self) {
            try SendProposalContext.parse(raw)
        }
    }

    @Test func rejectsDuplicateEventIds() {
        let raw: [String: Any] = [
            "casePath": "cases/x",
            "events": [
                [
                    "id": "e1",
                    "kind": "note",
                    "scope": "private",
                    "ownership": "you",
                    "at": "2026-10-20T11:40:00Z",
                    "summary": "a",
                    "source": ["vault": ["path": "a.md"]]
                ],
                [
                    "id": "e1",
                    "kind": "note",
                    "scope": "private",
                    "ownership": "you",
                    "at": "2026-10-21T11:40:00Z",
                    "summary": "b",
                    "source": ["vault": ["path": "b.md"]]
                ]
            ]
        ]
        #expect(throws: SendProposalContextError.self) {
            try SendProposalContext.parse(raw)
        }
    }

    @Test func rejectsUnknownKind() {
        let raw: [String: Any] = [
            "casePath": "cases/x",
            "events": [
                [
                    "id": "e1",
                    "kind": "sms",
                    "scope": "private",
                    "ownership": "you",
                    "at": "2026-10-20T11:40:00Z",
                    "summary": "x",
                    "source": ["vault": ["path": "LOG.md"]]
                ]
            ]
        ]
        #expect(throws: SendProposalContextError.self) {
            try SendProposalContext.parse(raw)
        }
    }

    @Test func rejectsMailKindWithoutMailSource() {
        let raw: [String: Any] = [
            "casePath": "cases/x",
            "events": [
                [
                    "id": "e1",
                    "kind": "mail",
                    "scope": "shared",
                    "ownership": "them",
                    "party": ["name": "Jo"],
                    "at": "2026-10-20T11:40:00Z",
                    "summary": "x",
                    "source": ["vault": ["path": "LOG.md"]]
                ]
            ]
        ]
        #expect(throws: SendProposalContextError.self) {
            try SendProposalContext.parse(raw)
        }
    }

    @Test func rejectsVaultKindWithoutVaultSource() {
        let raw: [String: Any] = [
            "casePath": "cases/x",
            "events": [
                [
                    "id": "e1",
                    "kind": "note",
                    "scope": "private",
                    "ownership": "you",
                    "at": "2026-10-20T11:40:00Z",
                    "summary": "x",
                    "source": [
                        "mail": ["accountID": "a", "placement": "INBOX", "id": "m"]
                    ]
                ]
            ]
        ]
        #expect(throws: SendProposalContextError.self) {
            try SendProposalContext.parse(raw)
        }
    }

    @Test func rejectsVaultPathEscape() {
        let raw: [String: Any] = [
            "casePath": "cases/x",
            "events": [
                [
                    "id": "e1",
                    "kind": "note",
                    "scope": "private",
                    "ownership": "you",
                    "at": "2026-10-20T11:40:00Z",
                    "summary": "x",
                    "source": ["vault": ["path": "../outside.md"]]
                ]
            ]
        ]
        #expect(throws: SendProposalContextError.self) {
            try SendProposalContext.parse(raw)
        }
    }

    @Test func defaultsCaseLabelFromPath() throws {
        let raw: [String: Any] = [
            "casePath": "cases/jobs/acme",
            "events": [
                [
                    "id": "e1",
                    "kind": "log",
                    "scope": "private",
                    "ownership": "you",
                    "at": "2026-10-20T11:40:00Z",
                    "summary": "x",
                    "source": ["vault": ["path": "LOG.md"]]
                ]
            ]
        ]
        let context = try SendProposalContext.parse(raw)
        #expect(context.caseLabel == "acme")
    }

    @Test func parseOptionalReturnsNilWhenMissing() throws {
        #expect(try SendProposalContext.parseOptional(nil) == nil)
        #expect(try SendProposalContext.parseOptional(NSNull()) == nil)
    }
}
