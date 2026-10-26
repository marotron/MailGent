import Foundation
import Testing
@testable import MailStore

@Suite struct FieldAskDecisionCacheTests {
    @Test func foreverPersistsAcrossRelaunch() throws {
        let url = temporaryAskDecisionsURL()
        defer { try? FileManager.default.removeItem(at: url) }

        let policy = AskDecisionCachePolicy(
            enabled: true,
            ttlSeconds: nil,
            persistAcrossLaunches: true,
            shareScope: .perAgent
        )
        let first = FieldAskDecisionCache(fileURL: url)
        first.store(
            .allow,
            agentID: "agent-a",
            accountID: "acct",
            placement: "INBOX",
            messageID: "1",
            field: "Body",
            policy: policy
        )

        let relaunched = FieldAskDecisionCache(fileURL: url)
        #expect(
            relaunched.decision(
                agentID: "agent-a",
                accountID: "acct",
                placement: "INBOX",
                messageID: "1",
                field: "Body",
                policy: policy
            ) == .allow
        )
    }

    @Test func expiredTTLMissesAndIsPrunedFromFile() throws {
        let url = temporaryAskDecisionsURL()
        defer { try? FileManager.default.removeItem(at: url) }

        let policy = AskDecisionCachePolicy(
            enabled: true,
            ttlSeconds: 60,
            persistAcrossLaunches: true,
            shareScope: .perAgent
        )
        let t0 = Date(timeIntervalSince1970: 1_000)
        let cache = FieldAskDecisionCache(fileURL: url)
        cache.store(
            .allow,
            agentID: "agent-a",
            accountID: "acct",
            placement: "INBOX",
            messageID: "1",
            field: "Body",
            policy: policy,
            now: t0
        )
        #expect(
            cache.decision(
                agentID: "agent-a",
                accountID: "acct",
                placement: "INBOX",
                messageID: "1",
                field: "Body",
                policy: policy,
                now: t0.addingTimeInterval(61)
            ) == nil
        )

        let relaunched = FieldAskDecisionCache(fileURL: url, now: t0.addingTimeInterval(61))
        #expect(
            relaunched.decision(
                agentID: "agent-a",
                accountID: "acct",
                placement: "INBOX",
                messageID: "1",
                field: "Body",
                policy: policy,
                now: t0.addingTimeInterval(61)
            ) == nil
        )
        #expect(!FileManager.default.fileExists(atPath: url.path))
    }

    @Test func untilQuitIsMemoryOnly() throws {
        let url = temporaryAskDecisionsURL()
        defer { try? FileManager.default.removeItem(at: url) }

        let untilQuit = AskDecisionCachePolicy(
            enabled: true,
            ttlSeconds: nil,
            persistAcrossLaunches: false,
            shareScope: .perAgent
        )
        let cache = FieldAskDecisionCache(fileURL: url)
        cache.store(
            .block,
            agentID: "agent-a",
            accountID: "acct",
            placement: "INBOX",
            messageID: "1",
            field: "Body",
            policy: untilQuit
        )
        #expect(
            cache.decision(
                agentID: "agent-a",
                accountID: "acct",
                placement: "INBOX",
                messageID: "1",
                field: "Body",
                policy: untilQuit
            ) == .block
        )
        #expect(!FileManager.default.fileExists(atPath: url.path))

        let relaunched = FieldAskDecisionCache(fileURL: url)
        #expect(
            relaunched.decision(
                agentID: "agent-a",
                accountID: "acct",
                placement: "INBOX",
                messageID: "1",
                field: "Body",
                policy: untilQuit
            ) == nil
        )
    }

    @Test func removeAllForAgentRewritesDisk() throws {
        let url = temporaryAskDecisionsURL()
        defer { try? FileManager.default.removeItem(at: url) }

        let policy = AskDecisionCachePolicy(
            enabled: true,
            ttlSeconds: 3_600,
            persistAcrossLaunches: true,
            shareScope: .perAgent
        )
        let cache = FieldAskDecisionCache(fileURL: url)
        cache.store(
            .allow,
            agentID: "keep",
            accountID: "acct",
            placement: "INBOX",
            messageID: "1",
            field: "Body",
            policy: policy
        )
        cache.store(
            .block,
            agentID: "drop",
            accountID: "acct",
            placement: "INBOX",
            messageID: "2",
            field: "Subject",
            policy: policy
        )
        cache.removeAll(forAgentID: "drop")

        let relaunched = FieldAskDecisionCache(fileURL: url)
        #expect(
            relaunched.decision(
                agentID: "keep",
                accountID: "acct",
                placement: "INBOX",
                messageID: "1",
                field: "Body",
                policy: policy
            ) == .allow
        )
        #expect(
            relaunched.decision(
                agentID: "drop",
                accountID: "acct",
                placement: "INBOX",
                messageID: "2",
                field: "Subject",
                policy: policy
            ) == nil
        )
    }

    private func temporaryAskDecisionsURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("MailGent-ask-decisions-\(UUID().uuidString).json")
    }
}
