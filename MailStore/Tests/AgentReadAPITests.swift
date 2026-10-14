import Foundation
import MailStore
import Testing

struct AgentReadAPITests {
    @Test func searchWithoutCredentialIsRejected() throws {
        let env = try AgentReadFixture()
        defer { env.remove() }

        #expect(throws: PairingError.unauthorized) {
            try env.gateway.search("invoice", credential: nil)
        }
    }

    @Test func searchWithWrongCredentialIsRejected() throws {
        let env = try AgentReadFixture()
        defer { env.remove() }

        #expect(throws: PairingError.unauthorized) {
            try env.gateway.search("invoice", credential: "wrong")
        }
    }

    @Test func authenticatedSearchReturnsGrantedMail() throws {
        let env = try AgentReadFixture()
        defer { env.remove() }

        let page = try env.gateway.search("invoice", credential: env.credential)
        #expect(page.items.map(\.subject) == ["Invoice due"])
    }

    @Test func getRedactsSecretsWhenLeakGuardEnabled() async throws {
        let env = try LeakGuardReadFixture(body: "password=hunter2\nPlease pay")
        defer { env.remove() }

        let message = try await env.gateway.get(
            credential: env.credential,
            accountID: env.accountID,
            placement: "INBOX",
            id: "1"
        )
        #expect(message.body == .text("[REDACTED:passwordCtx]\nPlease pay"))
        #expect(message.leakGuardAccess?.bodyAccess == .sanitized)
        #expect(message.leakGuardAccess?.sanitizedRules.contains("Password patterns") == true)
    }

    @Test func searchSanitizesSubjectWhenLeakGuardEnabled() throws {
        let env = try LeakGuardReadFixture(
            subject: "token=abc123 invoice",
            body: "Please pay"
        )
        defer { env.remove() }

        let page = try env.gateway.search("invoice", credential: env.credential)
        #expect(page.items.first?.subject == "[REDACTED:passwordCtx] invoice")
    }

    @Test func getWithholdsBodyWhenBlockWhole() async throws {
        let env = try LeakGuardReadFixture(
            body: "password=hunter2\nPlease pay",
            bodyHitMode: .blockWhole
        )
        defer { env.remove() }

        let message = try await env.gateway.get(
            credential: env.credential,
            accountID: env.accountID,
            placement: "INBOX",
            id: "1"
        )
        #expect(message.body == .text(""))
        #expect(message.leakGuardAccess?.bodyAccess == .withheldConfidential)
        #expect(message.leakGuardAccess?.bodyAccessReason == .leakGuard)
        #expect(message.leakGuardAccess?.sanitizedRules.contains("Password patterns") == true)
    }

    @Test func getStealthReplaceReportsGrantedBodyAccess() async throws {
        let rule = CustomLeakRule(
            label: "My name",
            kind: .literal,
            pattern: "Marotron",
            action: .replace,
            actionValue: "John Smith",
            discloseToAgent: false
        )
        let env = try LeakGuardReadFixture(
            body: "From Marotron",
            builtIns: [:],
            customRules: [rule]
        )
        defer { env.remove() }

        let message = try await env.gateway.get(
            credential: env.credential,
            accountID: env.accountID,
            placement: "INBOX",
            id: "1"
        )
        #expect(message.body == .text("From John Smith"))
        #expect(message.leakGuardAccess?.bodyAccess == .granted)
        #expect(message.leakGuardAccess?.bodyAccessReason == .grant)
        #expect(message.leakGuardAccess?.sanitizedRules.isEmpty == true)
        #expect(message.leakGuardAccess?.stealth == true)
    }

    @Test func getAuditRefRetainsOriginalsWhenSanitized() async throws {
        let env = try LeakGuardReadFixture(
            body: "password=hunter2\nPlease pay",
            audit: true
        )
        defer { env.remove() }

        _ = try await env.gateway.get(
            credential: env.credential,
            accountID: env.accountID,
            placement: "INBOX",
            id: "1"
        )
        let get = try #require(env.audit?.entries().last { $0.kind == .get })
        let response = leakGuardJSON(get.responseSummary)
        #expect(response["bodyAccess"] as? String == "sanitized")
        #expect(response["bodyAccessReason"] as? String == "leak_guard")
        #expect((response["sanitizedRules"] as? [String])?.contains("Password patterns") == true)
        #expect(get.messages.count == 1)
        #expect(get.messages[0].bodyOriginal == "password=hunter2\nPlease pay")
        #expect(get.messages[0].bodySnippet.contains("[REDACTED:passwordCtx]"))
        #expect(get.messages[0].sanitizedRules?.contains("Password patterns") == true)
        #expect(get.messages[0].bodyAccess == .sanitized)
        #expect(get.messages[0].leakDetectionCount >= 1)
        #expect(
            get.messages[0].leakDetections?.contains {
                $0.field == .body
                    && $0.label == "Password patterns"
                    && $0.disposition == .redacted
                    && $0.original.contains("password=hunter2")
            } == true
        )
    }

    @Test func getAuditRefRetainsStealthReplaceHits() async throws {
        let rule = CustomLeakRule(
            label: "My name",
            kind: .literal,
            pattern: "Marotron",
            action: .replace,
            actionValue: "John Smith",
            discloseToAgent: false
        )
        let env = try LeakGuardReadFixture(
            body: "From Marotron",
            builtIns: [:],
            customRules: [rule],
            audit: true
        )
        defer { env.remove() }

        _ = try await env.gateway.get(
            credential: env.credential,
            accountID: env.accountID,
            placement: "INBOX",
            id: "1"
        )
        let get = try #require(env.audit?.entries().last { $0.kind == .get })
        #expect(get.messages.count == 1)
        #expect(get.messages[0].bodyAccess == .sanitized)
        #expect(get.messages[0].stealth == true)
        #expect(get.messages[0].bodyOriginal == "From Marotron")
        #expect(get.messages[0].bodySnippet == "From John Smith")
        #expect(
            get.messages[0].leakDetections?.contains {
                $0.field == .body
                    && $0.label == "My name"
                    && $0.disposition == .replaced
                    && $0.original == "Marotron"
                    && $0.replacement == "John Smith"
                    && $0.discloseToAgent == false
            } == true
        )
    }

    @Test func getDoesNotScanDeniedBodyEvenWithLeakGuard() async throws {
        let env = try LeakGuardReadFixture(
            body: "password=hunter2\nPlease pay",
            bodyGranted: false
        )
        defer { env.remove() }

        let message = try await env.gateway.get(
            credential: env.credential,
            accountID: env.accountID,
            placement: "INBOX",
            id: "1"
        )
        #expect(message.body == .notGranted)
        #expect(message.leakGuardAccess?.bodyAccess == .notGranted)
        #expect(message.leakGuardAccess?.bodyAccessReason == .grant)
        #expect(message.leakGuardAccess?.sanitizedRules.isEmpty == true)
    }

    @Test func unprotectedScopeSkipsLeakGuardOnGet() async throws {
        let env = try LeakGuardReadFixture(
            body: "password=hunter2\nPlease pay",
            scopes: ["work/Sent"]
        )
        defer { env.remove() }

        let message = try await env.gateway.get(
            credential: env.credential,
            accountID: env.accountID,
            placement: "INBOX",
            id: "1"
        )
        #expect(message.body == .text("password=hunter2\nPlease pay"))
        #expect(message.leakGuardAccess?.bodyAccess == .granted)
    }

    @Test func matchingPassUpgradesBodyOnGet() async throws {
        let env = try AgentReadFixture(
            grantFields: GrantFields(envelope: true, body: false)
        )
        defer { env.remove() }

        let withoutPass = try await env.gateway.get(
            credential: env.credential,
            accountID: env.accountID,
            placement: "INBOX",
            id: "1"
        )
        #expect(withoutPass.body == .notGranted)

        env.rules.upsert(
            GrantRule(
                id: "p1",
                name: "Invoices",
                nick: "A",
                subjectRules: [MatchRule(value: "invoice", mode: .contains)],
                fields: GrantFields(envelope: false, body: true)
            )
        )
        env.rules.setEnabled(true, ruleID: "p1", agentID: env.agentID, accountID: env.accountID, placement: "INBOX")

        let withPass = try await env.gateway.get(
            credential: env.credential,
            accountID: env.accountID,
            placement: "INBOX",
            id: "1"
        )
        #expect(withPass.body == .text("Please pay"))
    }

    @Test func passDoesNotGrantAccessWithoutBaseAllow() async throws {
        let env = try AgentReadFixture(grantFields: nil)
        defer { env.remove() }

        env.rules.upsert(
            GrantRule(
                id: "p1",
                name: "Invoices",
                nick: "A",
                subjectRules: [MatchRule(value: "invoice", mode: .contains)],
                fields: GrantFields(envelope: false, body: true)
            )
        )
        env.rules.setEnabled(true, ruleID: "p1", agentID: env.agentID, accountID: env.accountID, placement: "INBOX")

        await #expect(throws: PairingError.unauthorized) {
            try await env.gateway.get(
                credential: env.credential,
                accountID: env.accountID,
                placement: "INBOX",
                id: "1"
            )
        }
    }

    @Test func passDoesNotUpgradeWhenSubjectMismatches() async throws {
        let env = try AgentReadFixture(
            grantFields: GrantFields(envelope: true, body: false)
        )
        defer { env.remove() }

        env.rules.upsert(
            GrantRule(
                id: "p1",
                name: "Receipts",
                nick: "A",
                subjectRules: [MatchRule(value: "receipt", mode: .contains)],
                fields: GrantFields(envelope: false, body: true)
            )
        )
        env.rules.setEnabled(true, ruleID: "p1", agentID: env.agentID, accountID: env.accountID, placement: "INBOX")

        let message = try await env.gateway.get(
            credential: env.credential,
            accountID: env.accountID,
            placement: "INBOX",
            id: "1"
        )
        #expect(message.body == .notGranted)
    }

    @Test func getAuditRecordsEffectfulPassApplication() async throws {
        let env = try AgentReadFixture(
            grantFields: GrantFields(envelope: true, body: false),
            audit: true
        )
        defer { env.remove() }

        env.rules.upsert(
            GrantRule(
                id: "p1",
                name: "Invoices",
                nick: "A",
                polarity: .pass,
                subjectRules: [MatchRule(value: "invoice", mode: .contains)],
                fields: GrantFields(envelope: false, body: true)
            )
        )
        env.rules.setEnabled(true, ruleID: "p1", agentID: env.agentID, accountID: env.accountID, placement: "INBOX")

        _ = try await env.gateway.get(
            credential: env.credential,
            accountID: env.accountID,
            placement: "INBOX",
            id: "1"
        )

        let get = env.audit!.entries().last { $0.kind == .get }!
        #expect(get.messages[0].appliedRules == [
            AppliedGrantRule(
                id: "p1",
                nick: "A",
                polarity: .pass,
                fields: GrantFields(envelope: false, body: true)
            )
        ])
        #expect(get.messages[0].passApplicationCount == 1)
        #expect(get.messages[0].passRevealedFields.body == true)
        #expect(get.messages[0].appliedRuleMark(for: \.body)?.nick == "A")
    }

    @Test func getAuditOmitsNoOpPassMatch() async throws {
        let env = try AgentReadFixture(
            grantFields: GrantFields(envelope: true, body: true),
            audit: true
        )
        defer { env.remove() }

        env.rules.upsert(
            GrantRule(
                id: "p1",
                name: "Invoices",
                nick: "A",
                polarity: .pass,
                subjectRules: [MatchRule(value: "invoice", mode: .contains)],
                fields: GrantFields(envelope: false, body: true)
            )
        )
        env.rules.setEnabled(true, ruleID: "p1", agentID: env.agentID, accountID: env.accountID, placement: "INBOX")

        _ = try await env.gateway.get(
            credential: env.credential,
            accountID: env.accountID,
            placement: "INBOX",
            id: "1"
        )

        let get = env.audit!.entries().last { $0.kind == .get }!
        #expect(get.messages[0].appliedRules == nil || get.messages[0].appliedRules?.isEmpty == true)
        #expect(get.messages[0].passApplicationCount == 0)
    }

    @Test func getAuditRecordsEffectfulBlockApplication() async throws {
        let env = try AgentReadFixture(
            grantFields: GrantFields(envelope: true, body: true),
            audit: true
        )
        defer { env.remove() }

        env.rules.upsert(
            GrantRule(
                id: "b1",
                name: "Hide body",
                nick: "B",
                polarity: .block,
                subjectRules: [MatchRule(value: "invoice", mode: .contains)],
                fields: GrantFields(envelope: false, body: true)
            )
        )
        env.rules.setEnabled(true, ruleID: "b1", agentID: env.agentID, accountID: env.accountID, placement: "INBOX")

        _ = try await env.gateway.get(
            credential: env.credential,
            accountID: env.accountID,
            placement: "INBOX",
            id: "1"
        )

        let get = env.audit!.entries().last { $0.kind == .get }!
        #expect(get.messages[0].appliedRules == [
            AppliedGrantRule(
                id: "b1",
                nick: "B",
                polarity: .block,
                fields: GrantFields(envelope: false, body: true)
            )
        ])
        #expect(get.messages[0].blockApplicationCount == 1)
        #expect(get.messages[0].blockWithheldFields.body == true)
        #expect(get.messages[0].appliedRuleMark(for: \.body)?.polarity == .block)
    }

    @Test func getAttachmentDeniedWhenContentNotGranted() async throws {
        let env = try AttachmentReadFixture(
            fields: GrantFields(
                envelope: true,
                body: true,
                attachmentMetadata: true,
                attachmentContent: false
            )
        )
        defer { env.remove() }

        let result = try await env.gateway.getAttachment(
            credential: env.credential,
            accountID: env.accountID,
            placement: "INBOX",
            id: "1",
            filename: "statement.pdf"
        )
        #expect(result.attachmentContentAccess == .notGranted)
        #expect(result.path == nil)
        #expect(result.filename == "statement.pdf")
    }

    @Test func getAttachmentWritesTempFileWhenContentGranted() async throws {
        let env = try AttachmentReadFixture(
            fields: GrantFields(
                envelope: true,
                body: true,
                attachmentMetadata: true,
                attachmentContent: true
            )
        )
        defer { env.remove() }

        let result = try await env.gateway.getAttachment(
            credential: env.credential,
            accountID: env.accountID,
            placement: "INBOX",
            id: "1",
            filename: "Statement.PDF"
        )
        #expect(result.attachmentContentAccess == .granted)
        let path = try #require(result.path)
        #expect(FileManager.default.fileExists(atPath: path))
        #expect(try Data(contentsOf: URL(fileURLWithPath: path)) == env.pdfBytes)
        #expect(result.byteCount == env.pdfBytes.count)
        #expect(result.filename == "statement.pdf")
    }

    @Test func getAttachmentUnauthorizedWithoutScope() async throws {
        let env = try AttachmentReadFixture(fields: nil)
        defer { env.remove() }

        await #expect(throws: PairingError.unauthorized) {
            try await env.gateway.getAttachment(
                credential: env.credential,
                accountID: env.accountID,
                placement: "INBOX",
                id: "1",
                filename: "statement.pdf"
            )
        }
    }

    @Test func getAttachmentUnknownFilenameIsNotAvailable() async throws {
        let env = try AttachmentReadFixture(
            fields: GrantFields(
                envelope: true,
                body: true,
                attachmentMetadata: true,
                attachmentContent: true
            )
        )
        defer { env.remove() }

        let result = try await env.gateway.getAttachment(
            credential: env.credential,
            accountID: env.accountID,
            placement: "INBOX",
            id: "1",
            filename: "missing.zip"
        )
        #expect(result.attachmentContentAccess == .notAvailable)
        #expect(result.path == nil)
    }

    @Test func getAttachmentUnknownFilenameIsNotAvailableEvenWhenContentBlocked() async throws {
        let env = try AttachmentReadFixture(
            fields: GrantFields(
                envelope: true,
                body: true,
                attachmentMetadata: true,
                attachmentContent: false
            )
        )
        defer { env.remove() }

        let result = try await env.gateway.getAttachment(
            credential: env.credential,
            accountID: env.accountID,
            placement: "INBOX",
            id: "1",
            filename: "missing.zip"
        )
        #expect(result.attachmentContentAccess == .notAvailable)
        #expect(result.note?.contains("No attachment named") == true)
        #expect(result.path == nil)
    }

    @Test func getAttachmentRejectsOversizedMetadata() async throws {
        let env = try AttachmentReadFixture(
            fields: GrantFields(
                envelope: true,
                body: true,
                attachmentMetadata: true,
                attachmentContent: true
            ),
            oversizedMetadata: true
        )
        defer { env.remove() }

        let result = try await env.gateway.getAttachment(
            credential: env.credential,
            accountID: env.accountID,
            placement: "INBOX",
            id: "1",
            filename: "huge.bin"
        )
        #expect(result.attachmentContentAccess == .tooLarge)
        #expect(result.path == nil)
        #expect((result.byteCount ?? 0) > AgentReadAPI.attachmentByteLimit)
    }

    @Test func getAttachmentHonoursAskContentAllowFromPriorGet() async throws {
        let env = try AttachmentReadFixture(
            fields: GrantFields(
                subjectMode: .on,
                fromMode: .on,
                toMode: .on,
                ccMode: .on,
                dateMode: .on,
                bodyMode: .on,
                attachmentMetadataMode: .ask,
                attachmentContentMode: .ask
            ),
            allowConditionalAccessPrompts: true,
            conditionalAccessPrompter: { _ in .allow }
        )
        defer { env.remove() }

        let message = try await env.gateway.get(
            credential: env.credential,
            accountID: env.accountID,
            placement: "INBOX",
            id: "1"
        )
        #expect(
            message.leakGuardAccess?.conditionalAccessFields.contains("Attachment content") == true
        )

        let result = try await env.gateway.getAttachment(
            credential: env.credential,
            accountID: env.accountID,
            placement: "INBOX",
            id: "1",
            filename: "statement.pdf"
        )
        #expect(result.attachmentContentAccess == .granted)
        let path = try #require(result.path)
        #expect(FileManager.default.fileExists(atPath: path))
        #expect(try Data(contentsOf: URL(fileURLWithPath: path)) == env.pdfBytes)
    }

    @Test func getAttachmentPromptsAskContentWhenUncached() async throws {
        final class PromptCapture: @unchecked Sendable {
            var fields: [String] = []
        }
        let capture = PromptCapture()
        let env = try AttachmentReadFixture(
            fields: GrantFields(
                subjectMode: .on,
                fromMode: .on,
                toMode: .on,
                ccMode: .on,
                dateMode: .on,
                bodyMode: .ask,
                attachmentMetadataMode: .ask,
                attachmentContentMode: .ask
            ),
            allowConditionalAccessPrompts: true,
            conditionalAccessPrompter: { context in
                capture.fields = context.requestedFields
                return .allow
            }
        )
        defer { env.remove() }

        let result = try await env.gateway.getAttachment(
            credential: env.credential,
            accountID: env.accountID,
            placement: "INBOX",
            id: "1",
            filename: "statement.pdf"
        )
        #expect(capture.fields == ["Attachment content"])
        #expect(result.attachmentContentAccess == .granted)
        let path = try #require(result.path)
        #expect(try Data(contentsOf: URL(fileURLWithPath: path)) == env.pdfBytes)
    }

    @Test func getAttachmentHonoursAskContentBlockFromPriorGet() async throws {
        let env = try AttachmentReadFixture(
            fields: GrantFields(
                subjectMode: .on,
                fromMode: .on,
                toMode: .on,
                ccMode: .on,
                dateMode: .on,
                bodyMode: .on,
                attachmentMetadataMode: .ask,
                attachmentContentMode: .ask
            ),
            allowConditionalAccessPrompts: true,
            conditionalAccessPrompter: { _ in .block }
        )
        defer { env.remove() }

        _ = try await env.gateway.get(
            credential: env.credential,
            accountID: env.accountID,
            placement: "INBOX",
            id: "1"
        )

        let result = try await env.gateway.getAttachment(
            credential: env.credential,
            accountID: env.accountID,
            placement: "INBOX",
            id: "1",
            filename: "statement.pdf"
        )
        #expect(result.attachmentContentAccess == .notGranted)
        #expect(result.path == nil)
        #expect(result.note?.contains("blocked Attachment Content on Ask") == true)
        #expect(result.note?.contains("enable Attachment Content on the grant") != true)
    }

    @Test func getAttachmentReusesAskContentAllowForSecondFile() async throws {
        final class PromptCounter: @unchecked Sendable {
            var count = 0
        }
        let counter = PromptCounter()
        let jpegBytes = Data("JPEG-BYTES".utf8)
        let env = try AttachmentReadFixture(
            fields: GrantFields(
                subjectMode: .on,
                fromMode: .on,
                toMode: .on,
                ccMode: .on,
                dateMode: .on,
                bodyMode: .on,
                attachmentMetadataMode: .ask,
                attachmentContentMode: .ask
            ),
            extraJPEGAttachment: jpegBytes,
            allowConditionalAccessPrompts: true,
            conditionalAccessPrompter: { context in
                counter.count += 1
                #expect(context.requestedFields.contains("Attachment content"))
                return .allow
            }
        )
        defer { env.remove() }

        _ = try await env.gateway.get(
            credential: env.credential,
            accountID: env.accountID,
            placement: "INBOX",
            id: "1"
        )
        #expect(counter.count == 1)

        let pdf = try await env.gateway.getAttachment(
            credential: env.credential,
            accountID: env.accountID,
            placement: "INBOX",
            id: "1",
            filename: "statement.pdf"
        )
        let jpeg = try await env.gateway.getAttachment(
            credential: env.credential,
            accountID: env.accountID,
            placement: "INBOX",
            id: "1",
            filename: "photo.jpeg"
        )
        #expect(pdf.attachmentContentAccess == .granted)
        #expect(jpeg.attachmentContentAccess == .granted)
        #expect(try Data(contentsOf: URL(fileURLWithPath: try #require(pdf.path))) == env.pdfBytes)
        #expect(try Data(contentsOf: URL(fileURLWithPath: try #require(jpeg.path))) == jpegBytes)
        #expect(counter.count == 1)
    }

    @Test func getTreatsAskBodyAsOffWhenConditionalDisabled() async throws {
        let env = try AgentReadFixture(
            grantFields: GrantFields(
                subjectMode: .on,
                fromMode: .on,
                toMode: .on,
                ccMode: .on,
                dateMode: .on,
                bodyMode: .ask
            ),
            allowConditionalAccessPrompts: false,
            conditionalAccessPrompter: { _ in .allow }
        )
        defer { env.remove() }

        let message = try await env.gateway.get(
            credential: env.credential,
            accountID: env.accountID,
            placement: "INBOX",
            id: "1"
        )
        #expect(message.body == .notGranted)
    }

    @Test func getPromptsAndAllowsAskBodyWhenConditionalEnabled() async throws {
        final class PromptCapture: @unchecked Sendable {
            var fields: [String] = []
        }
        let capture = PromptCapture()
        let env = try AgentReadFixture(
            grantFields: GrantFields(
                subjectMode: .on,
                fromMode: .on,
                toMode: .on,
                ccMode: .on,
                dateMode: .on,
                bodyMode: .ask
            ),
            audit: true,
            allowConditionalAccessPrompts: true,
            conditionalAccessPrompter: { context in
                capture.fields = context.requestedFields
                #expect(context.fieldPreviews.contains { $0.label == "Body" && $0.value == "Please pay" })
                return .allow
            }
        )
        defer { env.remove() }

        let message = try await env.gateway.get(
            credential: env.credential,
            accountID: env.accountID,
            placement: "INBOX",
            id: "1"
        )
        #expect(capture.fields == ["Body"])
        #expect(message.body == .text("Please pay"))
        #expect(message.leakGuardAccess?.bodyAccessReason == .conditional)
        #expect(message.leakGuardAccess?.conditionalAccessFields == ["Body"])
        let get = try #require(env.audit?.entries().last { $0.kind == .get })
        #expect(get.messages[0].conditionalConfirmedFields.body == true)
        #expect(leakGuardJSON(get.responseSummary)["bodyAccessReason"] as? String == "conditional")
        #expect(
            leakGuardJSON(get.responseSummary)["conditionalAccessFields"] as? [String] == ["Body"]
        )
    }

    @Test func getPromptsAndDeniesAskBodyWhenUserRefuses() async throws {
        let env = try AgentReadFixture(
            grantFields: GrantFields(
                subjectMode: .on,
                fromMode: .on,
                toMode: .on,
                ccMode: .on,
                dateMode: .on,
                bodyMode: .ask
            ),
            audit: true,
            allowConditionalAccessPrompts: true,
            conditionalAccessPrompter: { context in
                #expect(context.fieldPreviews.contains { $0.label == "Body" })
                return .block
            }
        )
        defer { env.remove() }

        let message = try await env.gateway.get(
            credential: env.credential,
            accountID: env.accountID,
            placement: "INBOX",
            id: "1"
        )
        #expect(message.body == .notGranted)
        #expect(message.leakGuardAccess?.bodyAccessReason == .conditionalBlocked)
        #expect(message.leakGuardAccess?.conditionalAccessFields == [])
        #expect(message.leakGuardAccess?.conditionalBlockedFields == ["Body"])
        let get = try #require(env.audit?.entries().last { $0.kind == .get })
        #expect(get.messages[0].conditionalUserBlockedFields.body == true)
        #expect(get.messages[0].conditionalConfirmedFields.body == false)
        #expect(
            leakGuardJSON(get.responseSummary)["bodyAccessReason"] as? String
                == "conditional_blocked"
        )
        #expect(
            leakGuardJSON(get.responseSummary)["conditionalBlockedFields"] as? [String] == ["Body"]
        )
    }

    @Test func askBodyPreviewDerivesPlainFromHTMLOnlyMail() async throws {
        final class PromptCapture: @unchecked Sendable {
            var bodyPreview = ""
            var bodyBadge: String?
            var htmlBody: String?
        }
        let capture = PromptCapture()
        let env = try AgentReadFixture(
            rfc822: """
            From: Promo <promo@example.com>
            To: Bob <bob@example.com>
            Subject: Payday sale
            Date: Mon, 1 Jan 2024 00:00:00 +0000
            MIME-Version: 1.0
            Content-Type: text/html; charset=utf-8

            <html><body><p>Extra 15% off in the payday sale</p></body></html>
            """,
            grantFields: GrantFields(
                subjectMode: .on,
                fromMode: .on,
                toMode: .on,
                ccMode: .on,
                dateMode: .on,
                bodyMode: .ask
            ),
            allowConditionalAccessPrompts: true,
            conditionalAccessPrompter: { context in
                let body = context.fieldPreviews.first { $0.label == "Body" }
                capture.bodyPreview = body?.value ?? ""
                capture.bodyBadge = body?.badge
                capture.htmlBody = context.htmlBody
                return .allow
            }
        )
        defer { env.remove() }

        let message = try await env.gateway.get(
            credential: env.credential,
            accountID: env.accountID,
            placement: "INBOX",
            id: "1"
        )
        #expect(capture.htmlBody?.contains("payday sale") == true)
        #expect(capture.bodyBadge == "HTML only")
        #expect(capture.bodyPreview.contains("Extra 15% off in the payday sale"))
        #expect(!capture.bodyPreview.hasPrefix("HTML only"))
        #expect(capture.bodyPreview != "(empty)")
        #expect(message.body != .notGranted)
    }

    @Test func askBodyPreviewLabelsHTMLOnlyWhenPlainStripIsEmpty() async throws {
        final class PromptCapture: @unchecked Sendable {
            var bodyPreview = ""
            var bodyBadge: String?
        }
        let capture = PromptCapture()
        let env = try AgentReadFixture(
            rfc822: """
            From: Promo <promo@example.com>
            To: Bob <bob@example.com>
            Subject: Image only
            Date: Mon, 1 Jan 2024 00:00:00 +0000
            MIME-Version: 1.0
            Content-Type: text/html; charset=utf-8

            <html><body><img src="cid:banner" alt=""></body></html>
            """,
            grantFields: GrantFields(
                subjectMode: .on,
                fromMode: .on,
                toMode: .on,
                ccMode: .on,
                dateMode: .on,
                bodyMode: .ask
            ),
            allowConditionalAccessPrompts: true,
            conditionalAccessPrompter: { context in
                let body = context.fieldPreviews.first { $0.label == "Body" }
                capture.bodyPreview = body?.value ?? ""
                capture.bodyBadge = body?.badge
                return .allow
            }
        )
        defer { env.remove() }

        _ = try await env.gateway.get(
            credential: env.credential,
            accountID: env.accountID,
            placement: "INBOX",
            id: "1"
        )
        #expect(capture.bodyBadge == "HTML only")
        #expect(capture.bodyPreview == "(empty)")
    }
}

private struct AgentReadFixture {
    let root: FixtureTree
    let db: URL
    let credential = "secret-token"
    let accountID = "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE"
    let agentID: String
    let rules: RuleStore
    let audit: AuditLog?
    let gateway: AgentReadAPI

    init(
        rfc822: String? = nil,
        grantFields: GrantFields? = .default,
        audit: Bool = false,
        allowConditionalAccessPrompts: Bool = false,
        conditionalAccessPrompter: (@Sendable (ConditionalAccessPromptContext) async -> ConditionalAccessDecision)? = nil
    ) throws {
        root = try FixtureTree()
        let defaultRFC822 = """
            From: Alice <alice@example.com>
            To: Bob <bob@example.com>
            Subject: Invoice due
            Date: Mon, 1 Jan 2024 00:00:00 +0000
            Content-Type: text/plain

            Please pay
            """
        try root.writeEmlx(
            named: "1.emlx",
            rfc822: rfc822 ?? defaultRFC822,
            account: accountID,
            mailbox: "INBOX.mbox"
        )

        db = FileManager.default.temporaryDirectory
            .appendingPathComponent("MailGent-agent-\(UUID().uuidString).sqlite")
        let index = try MailboxIndex(store: MailStore(root: root.mail), databaseURL: db)
        _ = try index.ingest()

        let auditLog = audit ? AuditLog() : nil
        self.audit = auditLog
        let pairing = Pairing(audit: auditLog)
        let agent = try pairing.register(
            name: "Cursor",
            trustClass: .machineLocal,
            credential: credential
        )
        agentID = agent.id
        let grants = GrantGate()
        if let grantFields {
            try grants.allow(agentID: agent.id, accountID: accountID, fields: grantFields)
        }
        rules = RuleStore()
        gateway = AgentReadAPI(
            read: ReadAPI(index: index),
            pairing: pairing,
            grants: grants,
            rules: rules,
            audit: auditLog,
            allowConditionalAccessPrompts: allowConditionalAccessPrompts,
            conditionalAccessPrompter: conditionalAccessPrompter
        )
    }

    func remove() {
        root.remove()
        try? FileManager.default.removeItem(at: db)
    }
}

private struct LeakGuardReadFixture {
    let root: FixtureTree
    let db: URL
    let credential = "secret-token"
    let accountID: String
    let audit: AuditLog?
    let gateway: AgentReadAPI

    init(
        subject: String = "Invoice due",
        body: String = "Please pay",
        bodyGranted: Bool = true,
        bodyHitMode: LeakGuardHitMode = .redactSpans,
        subjectHitMode: LeakGuardHitMode = .redactSpans,
        builtIns: [BuiltInLeakClass: Bool]? = [.passwordCtx: true],
        customRules: [CustomLeakRule] = [],
        scopes: Set<String>? = nil,
        audit: Bool = false
    ) throws {
        root = try FixtureTree()
        accountID = "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE"
        try root.writeEmlx(
            named: "1.emlx",
            rfc822: """
            From: Alice <alice@example.com>
            To: Bob <bob@example.com>
            Subject: \(subject)
            Date: Mon, 1 Jan 2024 00:00:00 +0000
            Content-Type: text/plain

            \(body)
            """,
            account: accountID,
            mailbox: "INBOX.mbox"
        )

        db = FileManager.default.temporaryDirectory
            .appendingPathComponent("MailGent-leak-\(UUID().uuidString).sqlite")
        let index = try MailboxIndex(store: MailStore(root: root.mail), databaseURL: db)
        _ = try index.ingest()

        let auditLog = audit ? AuditLog() : nil
        self.audit = auditLog
        let pairing = Pairing(audit: auditLog)
        let agent = try pairing.register(
            name: "Cursor",
            trustClass: .machineLocal,
            credential: credential
        )
        let grants = GrantGate()
        try grants.allow(
            agentID: agent.id,
            accountID: accountID,
            placement: "INBOX",
            fields: GrantFields(envelope: true, body: bodyGranted)
        )
        let scopeSet = scopes ?? [
            OutboundLeakGuardPolicy.scopeKey(accountID: accountID, placement: "INBOX")
        ]
        let policy = OutboundLeakGuardPolicy(
            enabled: true,
            scopes: scopeSet,
            builtInClasses: builtIns,
            customRules: customRules,
            subjectHitMode: subjectHitMode,
            bodyHitMode: bodyHitMode
        )
        gateway = AgentReadAPI(
            read: ReadAPI(index: index),
            pairing: pairing,
            grants: grants,
            leakGuard: OutboundLeakGuard(policy: policy),
            rules: RuleStore(),
            audit: auditLog
        )
    }

    func remove() {
        root.remove()
        try? FileManager.default.removeItem(at: db)
    }
}

private func leakGuardJSON(_ text: String) -> [String: Any] {
    guard let data = text.data(using: .utf8),
          let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
    else { return [:] }
    return obj
}

private struct AttachmentReadFixture {
    let root: FixtureTree
    let db: URL
    let credential = "secret-token"
    let accountID = "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE"
    let pdfBytes = Data("%PDF-1.4\nattachment-bytes".utf8)
    let gateway: AgentReadAPI

    init(
        fields: GrantFields?,
        oversizedMetadata: Bool = false,
        extraJPEGAttachment: Data? = nil,
        allowConditionalAccessPrompts: Bool = false,
        conditionalAccessPrompter: (@Sendable (ConditionalAccessPromptContext) async -> ConditionalAccessDecision)? = nil
    ) throws {
        root = try FixtureTree()
        if oversizedMetadata {
            let overLimit = AgentReadAPI.attachmentByteLimit + 1
            try root.writeEmlx(
                named: "1.partial.emlx",
                rfc822: """
                From: Alice <alice@example.com>
                To: Bob <bob@example.com>
                Subject: Big file
                Date: Mon, 1 Jan 2024 00:00:00 +0000
                MIME-Version: 1.0
                Content-Type: multipart/mixed; boundary="MIX"

                --MIX
                Content-Type: text/plain; charset=utf-8

                See attached.

                --MIX
                Content-Type: application/octet-stream; name="huge.bin"
                Content-Disposition: attachment; filename="huge.bin"
                X-Apple-Content-Length: \(overLimit)
                Content-Transfer-Encoding: base64


                --MIX--
                """,
                account: accountID,
                mailbox: "INBOX.mbox"
            )
        } else {
            let pdfB64 = pdfBytes.base64EncodedString()
            let jpegPart: String
            if let extraJPEGAttachment {
                let jpegB64 = extraJPEGAttachment.base64EncodedString()
                jpegPart = """

                --MIX
                Content-Type: image/jpeg; name="photo.jpeg"
                Content-Disposition: attachment; filename="photo.jpeg"
                Content-Transfer-Encoding: base64

                \(jpegB64)
                """
            } else {
                jpegPart = ""
            }
            try root.writeEmlx(
                named: "1.emlx",
                rfc822: """
                From: Alice <alice@example.com>
                To: Bob <bob@example.com>
                Subject: Statement
                Date: Mon, 1 Jan 2024 00:00:00 +0000
                MIME-Version: 1.0
                Content-Type: multipart/mixed; boundary="MIX"

                --MIX
                Content-Type: text/plain; charset=utf-8

                See statement.

                --MIX
                Content-Type: application/pdf; name="statement.pdf"
                Content-Disposition: attachment; filename="statement.pdf"
                Content-Transfer-Encoding: base64

                \(pdfB64)\(jpegPart)
                --MIX--
                """,
                account: accountID,
                mailbox: "INBOX.mbox"
            )
        }

        db = FileManager.default.temporaryDirectory
            .appendingPathComponent("MailGent-attach-\(UUID().uuidString).sqlite")
        let index = try MailboxIndex(store: MailStore(root: root.mail), databaseURL: db)
        _ = try index.ingest()

        let pairing = Pairing()
        let agent = try pairing.register(
            name: "Cursor",
            trustClass: .machineLocal,
            credential: credential
        )
        let grants = GrantGate()
        if let fields {
            try grants.allow(agentID: agent.id, accountID: accountID, fields: fields)
        }
        gateway = AgentReadAPI(
            read: ReadAPI(index: index),
            pairing: pairing,
            grants: grants,
            rules: RuleStore(),
            allowConditionalAccessPrompts: allowConditionalAccessPrompts,
            conditionalAccessPrompter: conditionalAccessPrompter
        )
    }

    func remove() {
        root.remove()
        try? FileManager.default.removeItem(at: db)
    }
}
