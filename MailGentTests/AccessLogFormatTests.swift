import MailStore
import Testing
@testable import MailGent

struct AccessLogFormatTests {
    @Test func emptyJSONObjectHasNoPrettyPairs() {
        #expect(AccessLogFormat.jsonPairs("{}")?.isEmpty == true)
        #expect(AccessLogFormat.jsonPairs("{ }")?.isEmpty == true)
        #expect(AccessLogFormat.jsonPairs("{\n}")?.isEmpty == true)
    }

    @Test func highlightedPrettyJSONPreservesTextAndSplitsColorRuns() {
        let json = #"{"ok":true,"n":1,"s":"hi","z":null}"#
        let pretty = AccessLogFormat.prettyJSON(json)
        let highlighted = AccessLogFormat.highlightedPrettyJSON(json)
        #expect(String(highlighted.characters) == pretty)
        let coloredRunCount = highlighted.runs.filter { $0.foregroundColor != nil }.count
        #expect(coloredRunCount >= 4)
    }

    @Test func statusJSONPrettyPairsAreKeyValues() {
        let json = """
        {"agentMayChangeSource":false,"indexedCount":18970,"lastIngestAt":"2026-08-22T22:37:13Z","newestMessageDate":"Sat, 22 Aug 2026 22:10:15 +0000","source":"liveMail"}
        """
        let pairs = AccessLogFormat.jsonPairs(json) ?? []
        #expect(pairs.map { "\($0.0)=\($0.1)" } == [
            "agentMayChangeSource=false",
            "indexedCount=18970",
            "lastIngestAt=2026-08-22T22:37:13Z",
            "newestMessageDate=Sat, 22 Aug 2026 22:10:15 +0000",
            "source=liveMail",
        ])
    }

    @Test func jsonPairsNilWhenNotAnObject() {
        #expect(AccessLogFormat.jsonPairs("not json") == nil)
        #expect(AccessLogFormat.jsonPairs("[1,2]") == nil)
        #expect(AccessLogFormat.jsonPairs("—") == nil)
    }

    @Test func displayValueDecodesAccountID() {
        #expect(
            AccessLogFormat.displayValue("accountID", "abc-uuid") { _ in "Work Gmail" }
                == "Work Gmail"
        )
        #expect(
            AccessLogFormat.displayValue("account", "abc-uuid") { _ in "Personal" }
                == "Personal"
        )
        #expect(
            AccessLogFormat.displayValue("query", "flights") { _ in "nope" }
                == "flights"
        )
    }

    @Test func displayValueFormatsMailDatesLocally() {
        let raw = "Fri, 28 Aug 2026 15:46:13 +0000"
        let formatted = AccessLogFormat.displayValue("newestMessageDate", raw) { _ in "" }
        #expect(formatted != raw)
        #expect(formatted.contains("28"))
        #expect(
            AccessLogFormat.displayValue("lastIngestAt", "2026-08-22T22:37:13Z") { _ in "" }
                != "2026-08-22T22:37:13Z"
        )
    }

    @Test func compactMailDateParsesRFC822() {
        let raw = "Sat, 22 Aug 2026 10:46:17 +0000"
        let formatted = AccessLogFormat.compactMailDate(raw)
        #expect(formatted != nil)
        #expect(formatted != raw)
        #expect(formatted?.contains("22") == true)
        #expect(AccessLogFormat.compactMailDate("") == nil)
        #expect(AccessLogFormat.compactMailDate("not-a-date") == "not-a-date")
    }

    @Test func jsonStringReadsNextCursor() {
        let json = #"{"count":5,"nextCursor":"100"}"#
        #expect(AccessLogFormat.jsonString(json, key: "nextCursor") == "100")
        #expect(AccessLogFormat.jsonString(json, key: "missing") == nil)
    }

    @Test func nestedJSONValueRendersCompact() {
        let json = #"{"count":1,"items":[{"id":"a"}]}"#
        let pairs = AccessLogFormat.jsonPairs(json) ?? []
        #expect(pairs.map { "\($0.0)=\($0.1)" } == [
            "count=1",
            #"items=[{"id":"a"}]"#,
        ])
    }

    @Test func matchesWordsEmptyQueryMatchesAnything() {
        #expect(AccessLogFormat.matchesWords("", in: ["hello"]))
        #expect(AccessLogFormat.matchesWords("   ", in: []))
        #expect(AccessLogFormat.matchesWords("\n\t", in: ["x"]))
    }

    @Test func matchesWordsRequiresEveryTokenInAnyText() {
        let request = #"{"query":"invoice"}"#
        let response = #"{"count":3,"items":[{"subject":"Invoice due"}]}"#
        #expect(AccessLogFormat.matchesWords("invoice 3", in: [request, response]))
        #expect(AccessLogFormat.matchesWords("due", in: [request, response]))
        #expect(!AccessLogFormat.matchesWords("invoice missing", in: [request, response]))
        #expect(!AccessLogFormat.matchesWords("invoice", in: ["", ""]))
    }

    @Test func matchesWordsIgnoresCaseAndDiacritics() {
        #expect(AccessLogFormat.matchesWords("INVOICE", in: [#"{"query":"invoice"}"#]))
        #expect(AccessLogFormat.matchesWords("cafe", in: ["subject: café"]))
        #expect(AccessLogFormat.matchesWords("CAFÉ", in: ["cafe"]))
    }

    @Test func isLargeStoreUsesCountOrByteThreshold() {
        #expect(!AccessLogFormat.isLargeStore(count: 0, bytes: 0))
        #expect(!AccessLogFormat.isLargeStore(count: 999, bytes: 1_048_575))
        #expect(AccessLogFormat.isLargeStore(count: 1_000, bytes: 0))
        #expect(AccessLogFormat.isLargeStore(count: 1, bytes: 1_048_576))
    }

    @Test func isEmptySuccessForZeroResultLookups() {
        let searchEmpty = AuditEntry(
            kind: .search,
            agentID: "a",
            agentName: "Grok Bot",
            responseSummary: #"{"count":0,"items":[]}"#
        )
        let searchHit = AuditEntry(
            kind: .search,
            agentID: "a",
            agentName: "Grok Bot",
            responseSummary: #"{"count":5,"items":[{}]}"#
        )
        let listEmpty = AuditEntry(
            kind: .list,
            agentID: "a",
            agentName: "Grok Bot",
            responseSummary: #"{"count":0,"items":[]}"#
        )
        let newEmpty = AuditEntry(
            kind: .listNew,
            agentID: "a",
            agentName: "Grok Bot",
            responseSummary: #"{"count":0,"items":[]}"#
        )
        let placementsEmpty = AuditEntry(
            kind: .listPlacements,
            agentID: "a",
            agentName: "Grok Bot",
            responseSummary: #"{"placements":[]}"#
        )
        let placementsHit = AuditEntry(
            kind: .listPlacements,
            agentID: "a",
            agentName: "Grok Bot",
            responseSummary: #"{"placements":["acct/INBOX"]}"#,
            placements: [AuditPlacementRef(accountID: "acct", placement: "INBOX")]
        )
        let getOk = AuditEntry(
            kind: .get,
            agentID: "a",
            agentName: "Grok Bot",
            responseSummary: #"{"id":"1"}"#
        )
        let searchError = AuditEntry(
            kind: .search,
            agentID: "a",
            agentName: "Grok Bot",
            responseSummary: #"{"count":0}"#,
            outcome: .error("boom")
        )

        #expect(AccessLogFormat.isEmptySuccess(searchEmpty))
        #expect(!AccessLogFormat.isEmptySuccess(searchHit))
        #expect(AccessLogFormat.isEmptySuccess(listEmpty))
        #expect(AccessLogFormat.isEmptySuccess(newEmpty))
        #expect(AccessLogFormat.isEmptySuccess(placementsEmpty))
        #expect(!AccessLogFormat.isEmptySuccess(placementsHit))
        #expect(!AccessLogFormat.isEmptySuccess(getOk))
        #expect(!AccessLogFormat.isEmptySuccess(searchError))
    }

    @Test func passAndBlockApplicationCountsSumDisplayMessages() {
        let entry = AuditEntry(
            kind: .list,
            agentID: "a",
            agentName: "Cursor",
            messages: [
                AuditMessageRef(
                    accountID: "acc",
                    placement: "INBOX",
                    id: "1",
                    subject: "A",
                    from: "a@example.com",
                    date: "2024-01-01T00:00:00Z",
                    appliedRules: [
                        AppliedGrantRule(
                            id: "p1",
                            nick: "A",
                            polarity: .pass,
                            fields: GrantFields(envelope: false, body: true)
                        ),
                        AppliedGrantRule(
                            id: "b1",
                            nick: "B",
                            polarity: .block,
                            fields: GrantFields(envelope: false, body: true)
                        )
                    ]
                ),
                AuditMessageRef(
                    accountID: "acc",
                    placement: "INBOX",
                    id: "2",
                    subject: "B",
                    from: "b@example.com",
                    date: "2024-01-02T00:00:00Z",
                    appliedRules: [
                        AppliedGrantRule(
                            id: "p2",
                            nick: "C",
                            polarity: .pass,
                            fields: GrantFields(envelope: false, body: true)
                        ),
                        AppliedGrantRule(
                            id: "p3",
                            nick: "D",
                            polarity: .pass,
                            fields: GrantFields(
                                subject: false,
                                from: false,
                                to: false,
                                cc: false,
                                date: false,
                                body: false,
                                attachmentMetadata: true
                            )
                        )
                    ]
                )
            ]
        )

        #expect(AccessLogFormat.passApplicationCount(for: entry) == 3)
        #expect(AccessLogFormat.blockApplicationCount(for: entry) == 1)
    }

    @Test func passAndBlockApplicationCountsZeroWhenNoAppliedRules() {
        let entry = AuditEntry(
            kind: .search,
            agentID: "a",
            agentName: "Cursor",
            messages: [
                AuditMessageRef(
                    accountID: "acc",
                    placement: "INBOX",
                    id: "1",
                    subject: "A",
                    from: "a@example.com",
                    date: "2024-01-01T00:00:00Z"
                )
            ]
        )

        #expect(AccessLogFormat.passApplicationCount(for: entry) == 0)
        #expect(AccessLogFormat.blockApplicationCount(for: entry) == 0)
    }

    @Test func attachmentContentMapsAccessStates() {
        func entry(_ responseSummary: String) -> AuditEntry {
            AuditEntry(
                kind: .getAttachment,
                agentID: "a",
                agentName: "Cursor",
                responseSummary: responseSummary
            )
        }

        let granted = AccessLogFormat.attachmentContent(
            for: entry(
                #"{"accountID":"acc","attachmentContentAccess":"granted","byteCount":95723,"filename":"statement.pdf","id":"1","placement":"INBOX"}"#
            )
        )
        #expect(granted?.state == .granted)
        #expect(granted?.filename == "statement.pdf")
        #expect(granted?.detailString.contains("statement.pdf") == true)

        let denied = AccessLogFormat.attachmentContent(
            for: entry(
                #"{"accountID":"acc","attachmentContentAccess":"not_granted","filename":"statement.pdf","id":"1","placement":"INBOX"}"#
            )
        )
        #expect(denied?.state == .denied)
        #expect(denied?.detailString == "not granted")
        #expect(denied?.previewBlockedReason != nil)

        let missing = AccessLogFormat.attachmentContent(
            for: entry(
                #"{"accountID":"acc","attachmentContentAccess":"not_available","filename":"statement.pdf","id":"1","placement":"INBOX"}"#
            )
        )
        #expect(missing?.state == .missing)
        #expect(missing?.detailString == "not available")

        let huge = AccessLogFormat.attachmentContent(
            for: entry(
                #"{"accountID":"acc","attachmentContentAccess":"too_large","byteCount":28000000,"filename":"statement.pdf","id":"1","placement":"INBOX"}"#
            )
        )
        #expect(huge?.state == .huge)
        #expect(huge?.detailString.contains("too large") == true)

        #expect(
            AccessLogFormat.attachmentContentDetail(
                for: entry(
                    #"{"attachmentContentAccess":"granted","byteCount":10,"filename":"statement.pdf"}"#
                )
            ).contains("statement.pdf")
        )
        #expect(
            AccessLogFormat.attachmentContent(
                for: AuditEntry(kind: .get, agentID: "a", agentName: "Cursor")
            ) == nil
        )
    }

    @Test func getAttachmentContentCardsUseMissingOrDeniedChrome() {
        let denied = AuditMessageRef(
            accountID: "acc",
            placement: "INBOX",
            id: "1",
            subject: "Bill",
            from: "a@example.com",
            date: "2024-01-01T00:00:00Z",
            fields: GrantFields(
                envelope: true,
                body: true,
                attachmentMetadata: true,
                attachmentContent: false
            ),
            attachments: [MailAttachment(filename: "a.pdf", byteCount: 10)]
        )
        let deniedCards = AccessLogFormat.getAttachmentContentCards(for: denied)
        #expect(deniedCards.count == 1)
        #expect(deniedCards[0].state == .denied)
        #expect(deniedCards[0].filename == "a.pdf")

        let omitted = AuditMessageRef(
            accountID: "acc",
            placement: "INBOX",
            id: "1",
            subject: "Bill",
            from: "a@example.com",
            date: "2024-01-01T00:00:00Z",
            fields: GrantFields(
                envelope: true,
                body: true,
                attachmentMetadata: true,
                attachmentContent: true
            ),
            attachments: [MailAttachment(filename: "a.pdf", byteCount: 10)]
        )
        let omittedCards = AccessLogFormat.getAttachmentContentCards(for: omitted)
        #expect(omittedCards.count == 1)
        #expect(omittedCards[0].state == .missing)
        #expect(omittedCards[0].stateLine.contains("get_attachment"))
    }
}
