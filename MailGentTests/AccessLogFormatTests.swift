import MailStore
import Testing
@testable import MailGent

struct AccessLogFormatTests {
    @Test func emptyJSONObjectHasNoPrettyPairs() {
        #expect(AccessLogFormat.jsonPairs("{}")?.isEmpty == true)
        #expect(AccessLogFormat.jsonPairs("{ }")?.isEmpty == true)
        #expect(AccessLogFormat.jsonPairs("{\n}")?.isEmpty == true)
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
}
