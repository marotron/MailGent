import Foundation
import Testing

@testable import MailStore

struct AuditLeakDetectionTests {
    // MARK: - Line helper

    @Test func lineNumberEmptyPrefixIsLineOne() {
        #expect(AuditLeakDetection.lineNumber(in: "secret", atCharacterOffset: 0) == 1)
        #expect(AuditLeakDetection.lineNumber(in: "", atCharacterOffset: 0) == 1)
    }

    @Test func lineNumberCountsNewlinesBeforeOffset() {
        let body = "one\ntwo\nthree"
        #expect(AuditLeakDetection.lineNumber(in: body, atCharacterOffset: 0) == 1) // "one"
        #expect(AuditLeakDetection.lineNumber(in: body, atCharacterOffset: 4) == 2) // "two"
        #expect(AuditLeakDetection.lineNumber(in: body, atCharacterOffset: 8) == 3) // "three"
    }

    @Test func lineNumberClampsPastEndToLastLine() {
        let body = "a\nb"
        #expect(AuditLeakDetection.lineNumber(in: body, atCharacterOffset: 99) == 2)
    }

    // MARK: - from(subject:body:)

    @Test func fromBodyHitsIncludeLineSubjectHitsDoNot() throws {
        let subjectOriginal = "invoice SECRET"
        let bodyOriginal = "hello\nworld SECRET here"
        // "SECRET" starts at character 8 in subject; at 12 in body (after "hello\nworld ").
        let subjectHit = LeakHitSpan(
            start: 8,
            end: 14,
            label: "Secret",
            source: "test",
            action: .redact,
            actionValue: "[REDACTED:Secret]",
            discloseToAgent: true
        )
        let bodyHit = LeakHitSpan(
            start: 12,
            end: 18,
            label: "Secret",
            source: "test",
            action: .redact,
            actionValue: "[REDACTED:Secret]",
            discloseToAgent: true
        )
        let subject = SanitizedField(
            text: "invoice [REDACTED:Secret]",
            access: .sanitized,
            agentAccess: .sanitized,
            reason: .leakGuard,
            disclosedRules: ["Secret"],
            allRules: ["Secret"],
            original: subjectOriginal,
            hitSpans: [subjectHit],
            stealth: false
        )
        let body = SanitizedField(
            text: "hello\nworld [REDACTED:Secret] here",
            access: .sanitized,
            agentAccess: .sanitized,
            reason: .leakGuard,
            disclosedRules: ["Secret"],
            allRules: ["Secret"],
            original: bodyOriginal,
            hitSpans: [bodyHit],
            stealth: false
        )

        let detections = AuditLeakDetection.from(subject: subject, body: body) ?? []
        #expect(detections.count == 2)

        let subjectDet = try #require(detections.first { $0.field == .subject })
        #expect(subjectDet.line == nil)
        #expect(subjectDet.original == "SECRET")

        let bodyDet = try #require(detections.first { $0.field == .body })
        #expect(bodyDet.line == 2)
        #expect(bodyDet.original == "SECRET")
    }

    @Test func decodeLegacyEntryMissingLineYieldsNil() throws {
        let json = """
        {
          "field": "body",
          "label": "Secret",
          "disposition": "redacted",
          "discloseToAgent": true,
          "original": "hunter2",
          "replacement": ""
        }
        """
        let data = Data(json.utf8)
        let decoded = try JSONDecoder().decode(AuditLeakDetection.self, from: data)
        #expect(decoded.line == nil)
        #expect(decoded.original == "hunter2")
        #expect(decoded.field == .body)
    }

    @Test func encodeDecodeRoundTripPreservesLine() throws {
        let detection = AuditLeakDetection(
            field: .body,
            label: "Secret",
            disposition: .redacted,
            discloseToAgent: true,
            original: "hunter2",
            replacement: "",
            line: 3
        )
        let data = try JSONEncoder().encode(detection)
        let decoded = try JSONDecoder().decode(AuditLeakDetection.self, from: data)
        #expect(decoded == detection)
        #expect(decoded.line == 3)
    }
}
