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

    public init(
        id: String = UUID().uuidString,
        agentName: String,
        to: [String],
        subject: String,
        body: String,
        cc: [String] = [],
        bcc: [String] = [],
        sender: String? = nil
    ) {
        self.id = id
        self.agentName = agentName
        self.to = to
        self.subject = subject
        self.body = body
        self.cc = cc
        self.bcc = bcc
        self.sender = sender
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
    public static func script(for proposal: SendProposal, mode: MailOutgoingMode) -> String {
        let visible = mode == .visibleCompose
        var lines: [String] = [
            "tell application \"Mail\"",
            "  activate",
            "  set newMessage to make new outgoing message with properties {subject:\"\(escape(proposal.subject))\", content:\"\(escape(proposal.body))\", visible:\(visible ? "true" : "false")}"
        ]
        if let sender = proposal.sender?.trimmingCharacters(in: .whitespacesAndNewlines), !sender.isEmpty {
            lines.append("  set sender of newMessage to \"\(escape(sender))\"")
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
        if mode == .send {
            lines.append("  send newMessage")
        }
        lines.append("end tell")
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
}
