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
        #expect(source.contains("set sender of newMessage to \"me@example.com\""))
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
        #expect(!source.contains("set sender of newMessage"))
    }

    @Test func splitDisplayAddress() {
        let named = MailOutgoingAppleScript.splitDisplayAddress("Alex Rivera <alex@example.com>")
        #expect(named.name == "Alex Rivera")
        #expect(named.email == "alex@example.com")
        let bare = MailOutgoingAppleScript.splitDisplayAddress("ops@example.com")
        #expect(bare.name == nil)
        #expect(bare.email == "ops@example.com")
    }
}
