import Foundation
import MailStore
import Testing

@Suite struct MailOutgoingAppleScriptTests {
    @Test func escapesQuotesAndBackslashes() {
        #expect(MailOutgoingAppleScript.escape(#"say "hi""#) == #"say \"hi\""#)
        #expect(MailOutgoingAppleScript.escape(#"a\b"#) == #"a\\b"#)
    }

    @Test func visibleComposeIncludesRecipientsSubjectBody() {
        let proposal = SendProposal(
            agentName: "Cursor",
            to: ["Alex <alex@example.com>", "ops@example.com"],
            subject: "Hello \"world\"",
            body: "Line 1\nLine 2",
            cc: ["cc@example.com"],
            bcc: ["bcc@example.com"],
            sender: "me@example.com"
        )
        let source = MailOutgoingAppleScript.script(for: proposal, mode: .visibleCompose)
        #expect(source.contains("tell application \"Mail\""))
        #expect(source.contains("visible:true"))
        #expect(!source.contains("\n  send newMessage"))
        #expect(source.contains(#"subject:"Hello \"world\""#))
        #expect(source.contains("content:\"Line 1\nLine 2\""))
        #expect(source.contains("set requestedEmail to \"me@example.com\""))
        #expect(source.contains("repeat with acct in accounts"))
        #expect(source.contains("email addresses of acct"))
        #expect(source.contains("sender:matchedSender"))
        #expect(source.contains("sender of newMessage"))
        #expect(source.contains("no Mail account matches From address"))
        #expect(source.contains("From address after compose"))
        #expect(!source.contains("set sender of newMessage to "))
        #expect(source.contains(
            #"make new to recipient at end of to recipients with properties {name:"Alex", address:"alex@example.com"}"#
        ))
        #expect(source.contains(
            #"make new to recipient at end of to recipients with properties {address:"ops@example.com"}"#
        ))
        #expect(source.contains(
            #"make new cc recipient at end of cc recipients with properties {address:"cc@example.com"}"#
        ))
        #expect(source.contains(
            #"make new bcc recipient at end of bcc recipients with properties {address:"bcc@example.com"}"#
        ))
    }

    @Test func sendModeUsesInvisibleComposeAndSend() {
        let proposal = SendProposal(
            agentName: "Cursor",
            to: ["alex@example.com"],
            subject: "Hi",
            body: "Body"
        )
        let source = MailOutgoingAppleScript.script(for: proposal, mode: .send)
        #expect(source.contains("visible:false"))
        #expect(source.contains("\n  send newMessage\n"))
        #expect(!source.contains("set requestedEmail to "))
        #expect(!source.contains("sender:matchedSender"))
    }

    @Test func sendModeWithSenderVerifiesFromBeforeSend() {
        let proposal = SendProposal(
            agentName: "Cursor",
            to: ["alex@example.com"],
            subject: "Hi",
            body: "Body",
            sender: "alt@example.com"
        )
        let source = MailOutgoingAppleScript.script(for: proposal, mode: .send)
        #expect(source.contains("set requestedEmail to \"alt@example.com\""))
        #expect(source.contains("sender:matchedSender"))
        #expect(source.contains("From address after compose"))
        guard let verifyRange = source.range(of: "From address after compose"),
              let sendRange = source.range(of: "\n  send newMessage\n")
        else {
            Issue.record("expected verify error text and send newMessage in script")
            return
        }
        #expect(verifyRange.lowerBound < sendRange.lowerBound)
    }

    @Test func splitDisplayAddress() {
        let named = MailOutgoingAppleScript.splitDisplayAddress("Alex Rivera <alex@example.com>")
        #expect(named.name == "Alex Rivera")
        #expect(named.email == "alex@example.com")
        let bare = MailOutgoingAppleScript.splitDisplayAddress("ops@example.com")
        #expect(bare.name == nil)
        #expect(bare.email == "ops@example.com")
    }

    @Test func emailAddressFromSenderStringExtractsAngleBracketEmail() {
        #expect(
            MailOutgoingAppleScript.emailAddress(fromSenderString: "Maro <a@b.c>") == "a@b.c"
        )
        #expect(
            MailOutgoingAppleScript.emailAddress(fromSenderString: "ops@example.com")
                == "ops@example.com"
        )
    }

    @Test func senderMatchesComparesEmailsCaseInsensitively() {
        #expect(
            MailOutgoingAppleScript.senderMatches(
                actual: "Maro <A@B.C>",
                expected: "a@b.c"
            )
        )
        #expect(
            !MailOutgoingAppleScript.senderMatches(
                actual: "Maro <other@example.com>",
                expected: "a@b.c"
            )
        )
    }

    @Test func emailsEquivalentTreatsGmailDotsAndGooglemailAsSameMailbox() {
        #expect(
            MailOutgoingAppleScript.emailsEquivalent(
                "mar.kuj.cv@gmail.com",
                "markujcv@gmail.com"
            )
        )
        #expect(
            MailOutgoingAppleScript.emailsEquivalent(
                "Mar.Kuj.Cv@googlemail.com",
                "markujcv@gmail.com"
            )
        )
        #expect(
            MailOutgoingAppleScript.emailsEquivalent(
                "Marek <mar.kuj.cv@gmail.com>",
                "markujcv@gmail.com"
            )
        )
        #expect(
            !MailOutgoingAppleScript.emailsEquivalent(
                "mar.kuj.cv@gmail.com",
                "markujawa@gmail.com"
            )
        )
        #expect(
            !MailOutgoingAppleScript.emailsEquivalent(
                "a.b@example.com",
                "ab@example.com"
            )
        )
    }

    @Test func senderScriptUsesMailboxEquivalenceWhenMatchingLiveAccounts() {
        let source = MailOutgoingAppleScript.script(
            for: SendProposal(
                agentName: "Cursor",
                to: ["alex@example.com"],
                subject: "Hi",
                body: "Body",
                sender: "mar.kuj.cv@gmail.com"
            ),
            mode: .visibleCompose
        )
        #expect(source.contains("gmail.com") || source.contains("googlemail.com"))
        #expect(source.contains("mailgentStripDots") || source.contains("stripDots"))
    }
}
