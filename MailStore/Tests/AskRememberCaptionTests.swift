import Testing
@testable import MailStore

@Suite struct AskRememberCaptionTests {
    @Test func disabledPolicyReturnsNil() {
        #expect(AskRememberCaption.note(for: .disabled) == nil)
    }

    @Test func formatsDurationAndShareScope() {
        let thirtyDays = AskDecisionCachePolicy(
            enabled: true,
            ttlSeconds: 2_592_000,
            persistAcrossLaunches: true,
            shareScope: .perAgent
        )
        #expect(
            AskRememberCaption.note(for: thirtyDays)
                == "will stay cached for 30 days (this agent)"
        )

        let foreverAll = AskDecisionCachePolicy(
            enabled: true,
            ttlSeconds: nil,
            persistAcrossLaunches: true,
            shareScope: .allAgents
        )
        #expect(
            AskRememberCaption.note(for: foreverAll)
                == "will stay cached for Forever (all agents)"
        )

        let untilQuit = AskDecisionCachePolicy(
            enabled: true,
            ttlSeconds: nil,
            persistAcrossLaunches: false,
            shareScope: .perAgent
        )
        #expect(
            AskRememberCaption.note(for: untilQuit)
                == "will stay cached for Until MailGent quits (this agent)"
        )
    }

    @Test func settingsTTLTagsMatchLabels() {
        #expect(AskRememberCaption.durationLabel(ttlSeconds: 900, persist: true) == "15 minutes")
        #expect(AskRememberCaption.durationLabel(ttlSeconds: 3_600, persist: true) == "1 hour")
        #expect(AskRememberCaption.durationLabel(ttlSeconds: 86_400, persist: true) == "24 hours")
        #expect(AskRememberCaption.durationLabel(ttlSeconds: 2_592_000, persist: true) == "30 days")
        #expect(AskRememberCaption.durationLabel(ttlSeconds: 31_536_000, persist: true) == "1 year")
    }
}
