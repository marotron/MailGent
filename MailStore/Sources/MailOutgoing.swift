import Foundation

/// One agent-proposed new message awaiting human confirmation.
public struct SendProposal: Equatable, Sendable {
    public let id: String
    public let agentName: String
    public let to: [String]
    public let subject: String
    public let body: String
    public let cc: [String]
    public let bcc: [String]
    /// Optional From / account address for Mail.app `sender`.
    public let sender: String?
    /// Optional Assembly-C context thread (experimental; ignored when Settings toggle off).
    public let context: SendProposalContext?

    public init(
        id: String = UUID().uuidString,
        agentName: String,
        to: [String],
        subject: String,
        body: String,
        cc: [String] = [],
        bcc: [String] = [],
        sender: String? = nil,
        context: SendProposalContext? = nil
    ) {
        self.id = id
        self.agentName = agentName
        self.to = to
        self.subject = subject
        self.body = body
        self.cc = cc
        self.bcc = bcc
        self.sender = sender
        self.context = context
    }
}

/// User choice on a send proposal. Distinct from Ask Allow/Block.
public enum SendProposalDecision: String, Equatable, Sendable {
    case send
    case openInMail
    case cancel
}

/// How to hand the message to Mail.app after confirmation.
public enum MailOutgoingMode: Equatable, Sendable {
    /// Compose then `send` (may stay invisible).
    case send
    /// Leave a visible compose window; do not send.
    case visibleCompose
}

/// App-hosted adapter that runs AppleScript / Apple Events into Mail.app.
public protocol MailOutgoingSending: Sendable {
    func deliver(_ proposal: SendProposal, mode: MailOutgoingMode) throws
}

public enum MailOutgoingError: Error, Equatable, CustomStringConvertible, Sendable {
    case scriptFailed(String)

    public var description: String {
        switch self {
        case .scriptFailed(let message):
            return message.isEmpty ? "Apple Mail scripting failed." : message
        }
    }
}

/// Pure AppleScript source builder for a new outgoing message (no AppKit).
public enum MailOutgoingAppleScript {
    /// Escape a value for an AppleScript quoted string.
    public static func escape(_ value: String) -> String {
        value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
    }

    /// Build a `tell application "Mail"` script for `proposal` in `mode`.
    ///
    /// When `proposal.sender` is set, resolves against Mail’s live `accounts` /
    /// `email addresses`, sets `sender` in `make new outgoing message with properties`,
    /// and errors if the composed From email does not match (fail closed — no silent default).
    public static func script(for proposal: SendProposal, mode: MailOutgoingMode) -> String {
        let visible = mode == .visibleCompose
        let requestedSender = proposal.sender?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let hasSender = !(requestedSender ?? "").isEmpty

        var lines: [String] = [
            "tell application \"Mail\"",
            "  activate"
        ]

        if let requested = requestedSender, hasSender {
            let escaped = escape(requested)
            lines.append(contentsOf: [
                "  set requestedEmail to \"\(escaped)\"",
                "  set matchedEmail to missing value",
                "  set matchedSender to missing value",
                "  repeat with acct in accounts",
                "    try",
                "      set addrs to email addresses of acct",
                "    on error",
                "      set addrs to {}",
                "    end try",
                "    if class of addrs is string then set addrs to {addrs}",
                "    repeat with addr in addrs",
                "      set addrText to addr as string",
                "      set addrMatch to false",
                "      if addrText is equal to requestedEmail then",
                "        set addrMatch to true",
                "      else",
                "        set reqAt to offset of \"@\" in requestedEmail",
                "        set addrAt to offset of \"@\" in addrText",
                "        if reqAt > 1 and addrAt > 1 then",
                "          set reqLocal to text 1 thru (reqAt - 1) of requestedEmail",
                "          set reqHost to text (reqAt + 1) thru -1 of requestedEmail",
                "          set addrLocal to text 1 thru (addrAt - 1) of addrText",
                "          set addrHost to text (addrAt + 1) thru -1 of addrText",
                "          if (reqHost is \"gmail.com\" or reqHost is \"googlemail.com\") and (addrHost is \"gmail.com\" or addrHost is \"googlemail.com\") then",
                "            if (my mailgentStripDots(reqLocal)) is equal to (my mailgentStripDots(addrLocal)) then set addrMatch to true",
                "          end if",
                "        end if",
                "      end if",
                "      if addrMatch then",
                "        set fullNameText to \"\"",
                "        try",
                "          set fullNameText to full name of acct as string",
                "        end try",
                "        if fullNameText is \"\" then",
                "          set matchedSender to addrText",
                "        else",
                "          set matchedSender to fullNameText & \" <\" & addrText & \">\"",
                "        end if",
                "        set matchedEmail to addrText",
                "        exit repeat",
                "      end if",
                "    end repeat",
                "    if matchedEmail is not missing value then exit repeat",
                "  end repeat",
                "  if matchedEmail is missing value then error \"MailGent: no Mail account matches From address \\\"\" & requestedEmail & \"\\\".\"",
                "  set newMessage to make new outgoing message with properties {subject:\"\(escape(proposal.subject))\", content:\"\(escape(proposal.body))\", visible:\(visible ? "true" : "false"), sender:matchedSender}"
            ])
        } else {
            lines.append(
                "  set newMessage to make new outgoing message with properties {subject:\"\(escape(proposal.subject))\", content:\"\(escape(proposal.body))\", visible:\(visible ? "true" : "false")}"
            )
        }

        lines.append("  tell newMessage")
        for address in proposal.to {
            lines.append(recipientLine(kind: "to", address: address))
        }
        for address in proposal.cc {
            lines.append(recipientLine(kind: "cc", address: address))
        }
        for address in proposal.bcc {
            lines.append(recipientLine(kind: "bcc", address: address))
        }
        lines.append("  end tell")

        if hasSender {
            lines.append(contentsOf: [
                "  set actualSender to sender of newMessage as string",
                "  set actualEmail to actualSender",
                "  set openPos to offset of \"<\" in actualSender",
                "  set closePos to offset of \">\" in actualSender",
                "  if openPos > 0 and closePos > openPos then",
                "    set actualEmail to text (openPos + 1) thru (closePos - 1) of actualSender",
                "  end if",
                "  if actualEmail is not equal to matchedEmail then error \"MailGent: From address after compose was \\\"\" & actualSender & \"\\\", expected \\\"\" & matchedEmail & \"\\\".\""
            ])
        }

        if mode == .send {
            lines.append("  send newMessage")
        }
        lines.append("end tell")
        if hasSender {
            lines.append(contentsOf: [
                "",
                "on mailgentStripDots(s)",
                "  set outText to \"\"",
                "  repeat with ch in characters of s",
                "    if (ch as string) is not \".\" then set outText to outText & ch",
                "  end repeat",
                "  return outText",
                "end mailgentStripDots"
            ])
        }
        return lines.joined(separator: "\n")
    }

    private static func recipientLine(kind: String, address: String) -> String {
        let trimmed = address.trimmingCharacters(in: .whitespacesAndNewlines)
        let (name, email) = splitDisplayAddress(trimmed)
        let props: String
        if let name, !name.isEmpty {
            props = "{name:\"\(escape(name))\", address:\"\(escape(email))\"}"
        } else {
            props = "{address:\"\(escape(email))\"}"
        }
        return "    make new \(kind) recipient at end of \(kind) recipients with properties \(props)"
    }

    /// `"Name <a@b.c>"` → (Name, a@b.c); bare address → (nil, address).
    public static func splitDisplayAddress(_ raw: String) -> (name: String?, email: String) {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let open = trimmed.lastIndex(of: "<"),
              let close = trimmed.lastIndex(of: ">"),
              open < close
        else {
            return (nil, trimmed)
        }
        let email = String(trimmed[trimmed.index(after: open)..<close])
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let name = String(trimmed[..<open]).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !email.isEmpty else { return (nil, trimmed) }
        return (name.isEmpty ? nil : name, email)
    }

    /// Email portion of a Mail `sender` / display string (`"Name <a@b.c>"` or bare).
    public static func emailAddress(fromSenderString raw: String) -> String {
        splitDisplayAddress(raw).email
    }

    /// True when `actual` and `expected` refer to the same mailbox (case-insensitive email,
    /// plus Gmail / Googlemail local-part dot equivalence).
    public static func senderMatches(actual: String, expected: String) -> Bool {
        emailsEquivalent(actual, expected)
    }

    /// Same mailbox for allow-list and Mail From matching.
    /// Gmail / Googlemail: ignore dots in the local part and treat hosts as equivalent.
    /// Other providers: case-insensitive exact email only.
    public static func emailsEquivalent(_ lhs: String, _ rhs: String) -> Bool {
        let a = emailAddress(fromSenderString: lhs)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let b = emailAddress(fromSenderString: rhs)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if a.caseInsensitiveCompare(b) == .orderedSame {
            return true
        }
        guard let keyA = gmailMailboxKey(a), let keyB = gmailMailboxKey(b) else {
            return false
        }
        return keyA == keyB
    }

    /// `local@gmail.com` with dots stripped from `local`, or `nil` if not Gmail/Googlemail.
    static func gmailMailboxKey(_ email: String) -> String? {
        guard let at = email.firstIndex(of: "@") else { return nil }
        let local = String(email[..<at])
        let host = String(email[email.index(after: at)...]).lowercased()
        guard host == "gmail.com" || host == "googlemail.com" else { return nil }
        let stripped = local
            .replacingOccurrences(of: ".", with: "")
            .lowercased()
        guard !stripped.isEmpty else { return nil }
        return stripped + "@gmail.com"
    }
}
