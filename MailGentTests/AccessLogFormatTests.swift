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
}
