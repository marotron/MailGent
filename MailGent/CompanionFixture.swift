import Foundation

enum CompanionAccounts {
    static let work = "11111111-1111-1111-1111-111111111111"
    static let personal = "22222222-2222-2222-2222-222222222222"

    static func label(_ accountID: String) -> String {
        switch accountID {
        case work: "Work Gmail"
        case personal: "Personal"
        default: String(accountID.prefix(8))
        }
    }
}

enum CompanionFixture {
    static func plant(at root: URL) throws {
        for message in seed {
            try write(message, at: root)
        }
    }

    static func plantArrival(at root: URL, wave: Int) throws {
        let n = wave + 1
        let arrivals: [Seed] = [
            Seed(
                name: "w\(wave)-a.emlx",
                from: "Standup bot <bot@company.com>",
                to: "you@company.com",
                subject: "Standup notes \(n)",
                date: "Wed, 19 Aug 2026 08:1\(wave % 10):00 +0000",
                body: "Yesterday: index work. Today: ingest wave \(n). Blockers: none.",
                account: CompanionAccounts.work,
                mailbox: "INBOX.mbox"
            ),
            Seed(
                name: "w\(wave)-b.emlx",
                from: "CI <ci@company.com>",
                to: "you@company.com",
                subject: "Build \(n) passed",
                date: "Wed, 19 Aug 2026 09:2\(wave % 10):00 +0000",
                body: "mailgent-macos #\(40 + wave) is green on arm64.",
                account: CompanionAccounts.work,
                mailbox: "INBOX.mbox"
            ),
            Seed(
                name: "w\(wave)-c.emlx",
                from: "Calendar <calendar@company.com>",
                to: "you@company.com",
                subject: "Reminder: 1:1 in 15 minutes",
                date: "Wed, 19 Aug 2026 10:0\(wave % 10):00 +0000",
                body: "With Ava Chen. Wave \(n) agenda is in the doc.",
                account: CompanionAccounts.work,
                mailbox: "INBOX.mbox"
            ),
            Seed(
                name: "w\(wave)-d.emlx",
                from: "Receipts <receipts@personal.example>",
                to: "you@personal.example",
                subject: "Order \(1200 + wave) confirmed",
                date: "Wed, 19 Aug 2026 11:4\(wave % 10):00 +0000",
                body: "Thanks. Your items ship tomorrow. Wave \(n).",
                account: CompanionAccounts.personal,
                mailbox: "INBOX.mbox"
            ),
        ]
        for message in arrivals {
            try write(message, at: root)
        }
    }

    private struct Seed {
        var name: String
        var from: String
        var to: String
        var subject: String
        var date: String
        var body: String
        var account: String
        var mailbox: String
    }

    private static let seed: [Seed] = [
        Seed(
            name: "1.emlx",
            from: "Ava Chen <ava@company.com>",
            to: "you@company.com",
            subject: "Q3 planning notes",
            date: "Mon, 19 Aug 2024 10:32:00 +0000",
            body: "Here is the revised schedule and proposed next steps for quarterly planning.",
            account: CompanionAccounts.work,
            mailbox: "INBOX.mbox"
        ),
        Seed(
            name: "2.emlx",
            from: "Product team <product@company.com>",
            to: "you@company.com",
            subject: "Planning workshop follow-up",
            date: "Fri, 16 Aug 2024 16:05:00 +0000",
            body: "Thanks for joining. Notes and actions from the planning workshop are attached.",
            account: CompanionAccounts.work,
            mailbox: "INBOX.mbox"
        ),
        Seed(
            name: "3.emlx",
            from: "you@company.com",
            to: "Ava Chen <ava@company.com>",
            subject: "Re: Q3 planning notes",
            date: "Mon, 19 Aug 2024 11:04:00 +0000",
            body: "Confirmed for Tuesday. I will send the planning deck before noon.",
            account: CompanionAccounts.work,
            mailbox: "Sent Messages.mbox"
        ),
        Seed(
            name: "4.emlx",
            from: "Marcus Ltd. <statements@marcus.example>",
            to: "you@personal.example",
            subject: "Quarterly statement ready",
            date: "Sun, 18 Aug 2024 09:12:00 +0000",
            body: "Your new statement is ready to review in the portal.",
            account: CompanionAccounts.personal,
            mailbox: "INBOX.mbox"
        ),
        Seed(
            name: "7.partial.emlx",
            from: "Photos <photos@personal.example>",
            to: "you@personal.example",
            subject: "Download remaining",
            date: "Sat, 17 Aug 2024 14:20:00 +0000",
            body: "has stub",
            account: CompanionAccounts.personal,
            mailbox: "INBOX.mbox"
        ),
        Seed(
            name: "8.emlx",
            from: "Receipts <receipts@personal.example>",
            to: "you@personal.example",
            subject: "Empty receipt",
            date: "Thu, 15 Aug 2024 08:00:00 +0000",
            body: "",
            account: CompanionAccounts.personal,
            mailbox: "Archive.mbox"
        ),
        Seed(
            name: "10.emlx",
            from: "Jordan Lee <jordan@company.com>",
            to: "you@company.com",
            subject: "Design review Thursday",
            date: "Tue, 18 Aug 2026 09:15:00 +0000",
            body: "Can we move design review to 15:00? I will share the Figma link before lunch.",
            account: CompanionAccounts.work,
            mailbox: "INBOX.mbox"
        ),
        Seed(
            name: "11.emlx",
            from: "IT Security <security@company.com>",
            to: "you@company.com",
            subject: "VPN certificate expires Friday",
            date: "Mon, 17 Aug 2026 07:40:00 +0000",
            body: "Renew the office VPN cert before Friday or you will be locked out of staging.",
            account: CompanionAccounts.work,
            mailbox: "INBOX.mbox"
        ),
        Seed(
            name: "12.emlx",
            from: "Hiring <hiring@company.com>",
            to: "you@company.com",
            subject: "Interview loop: Maya Patel",
            date: "Sun, 16 Aug 2026 19:22:00 +0000",
            body: "Maya is on-site Wednesday. Please take the systems interview slot at 11:00.",
            account: CompanionAccounts.work,
            mailbox: "INBOX.mbox"
        ),
        Seed(
            name: "13.emlx",
            from: "Legal <legal@company.com>",
            to: "you@company.com",
            subject: "DPA for MailGent vendors",
            date: "Fri, 14 Aug 2026 13:05:00 +0000",
            body: "Please confirm the data processing addendum before we enable the new vendor.",
            account: CompanionAccounts.work,
            mailbox: "INBOX.mbox"
        ),
        Seed(
            name: "14.emlx",
            from: "Office <office@company.com>",
            to: "you@company.com",
            subject: "Desk booking next week",
            date: "Thu, 13 Aug 2026 16:48:00 +0000",
            body: "Tuesday and Thursday are already at capacity. Book a desk if you plan to come in.",
            account: CompanionAccounts.work,
            mailbox: "INBOX.mbox"
        ),
        Seed(
            name: "15.emlx",
            from: "Ava Chen <ava@company.com>",
            to: "you@company.com",
            subject: "Re: planning deck",
            date: "Wed, 12 Aug 2026 18:11:00 +0000",
            body: "Slide 7 still has last quarter’s numbers. Can you swap in the August snapshot?",
            account: CompanionAccounts.work,
            mailbox: "INBOX.mbox"
        ),
        Seed(
            name: "16.emlx",
            from: "Support <support@company.com>",
            to: "you@company.com",
            subject: "Customer asked about export",
            date: "Tue, 11 Aug 2026 10:03:00 +0000",
            body: "Acme wants a mailbox export for their legal hold. Is that in scope for local-read?",
            account: CompanionAccounts.work,
            mailbox: "INBOX.mbox"
        ),
        Seed(
            name: "17.emlx",
            from: "you@company.com",
            to: "Jordan Lee <jordan@company.com>",
            subject: "Re: Design review Thursday",
            date: "Tue, 18 Aug 2026 09:40:00 +0000",
            body: "15:00 works. I will add the prototype screenshots to the review doc.",
            account: CompanionAccounts.work,
            mailbox: "Sent Messages.mbox"
        ),
        Seed(
            name: "18.emlx",
            from: "you@company.com",
            to: "Hiring <hiring@company.com>",
            subject: "Re: Interview loop: Maya Patel",
            date: "Sun, 16 Aug 2026 20:01:00 +0000",
            body: "Booked. Sending a scorecard template this evening.",
            account: CompanionAccounts.work,
            mailbox: "Sent Messages.mbox"
        ),
        Seed(
            name: "19.emlx",
            from: "you@company.com",
            to: "Legal <legal@company.com>",
            subject: "Re: DPA for MailGent vendors",
            date: "Fri, 14 Aug 2026 15:22:00 +0000",
            body: "Reviewed. One question on subprocessors — see comments in the doc.",
            account: CompanionAccounts.work,
            mailbox: "Sent Messages.mbox"
        ),
        Seed(
            name: "20.emlx",
            from: "School <office@school.example>",
            to: "you@personal.example",
            subject: "Inset day 4 September",
            date: "Mon, 18 Aug 2026 08:30:00 +0000",
            body: "School is closed for staff training on 4 September. Wraparound care is unavailable.",
            account: CompanionAccounts.personal,
            mailbox: "INBOX.mbox"
        ),
        Seed(
            name: "21.emlx",
            from: "Dentist <hello@practice.example>",
            to: "you@personal.example",
            subject: "Appointment reminder",
            date: "Sun, 17 Aug 2026 12:00:00 +0000",
            body: "Your checkup is Thursday at 08:20. Reply CANCEL if you need to move it.",
            account: CompanionAccounts.personal,
            mailbox: "INBOX.mbox"
        ),
        Seed(
            name: "22.emlx",
            from: "Council <noreply@city.example>",
            to: "you@personal.example",
            subject: "Bin collection moved",
            date: "Sat, 16 Aug 2026 06:12:00 +0000",
            body: "Garden waste moves to Friday this week because of the bank holiday.",
            account: CompanionAccounts.personal,
            mailbox: "INBOX.mbox"
        ),
        Seed(
            name: "23.emlx",
            from: "Bank <alerts@bank.example>",
            to: "you@personal.example",
            subject: "New login from Safari",
            date: "Fri, 15 Aug 2026 21:44:00 +0000",
            body: "We noticed a new sign-in. If this was you, no action needed.",
            account: CompanionAccounts.personal,
            mailbox: "INBOX.mbox"
        ),
        Seed(
            name: "24.emlx",
            from: "Flights <trips@airline.example>",
            to: "you@personal.example",
            subject: "Boarding pass: EDI → LHR",
            date: "Thu, 14 Aug 2026 05:55:00 +0000",
            body: "Check-in is open. Seat 14A. Gate published 90 minutes before departure.",
            account: CompanionAccounts.personal,
            mailbox: "INBOX.mbox"
        ),
        Seed(
            name: "25.emlx",
            from: "Landlord <lets@housing.example>",
            to: "you@personal.example",
            subject: "Inspection next Tuesday",
            date: "Wed, 13 Aug 2026 11:17:00 +0000",
            body: "Annual inspection between 10:00 and 12:00. Someone 18+ must be home.",
            account: CompanionAccounts.personal,
            mailbox: "INBOX.mbox"
        ),
        Seed(
            name: "26.emlx",
            from: "Bookstore <orders@books.example>",
            to: "you@personal.example",
            subject: "Your order has shipped",
            date: "Tue, 12 Aug 2026 14:09:00 +0000",
            body: "Tracking is live. Estimated delivery Thursday.",
            account: CompanionAccounts.personal,
            mailbox: "Archive.mbox"
        ),
        Seed(
            name: "27.emlx",
            from: "Insurance <claims@cover.example>",
            to: "you@personal.example",
            subject: "Policy renewal",
            date: "Mon, 11 Aug 2026 09:00:00 +0000",
            body: "Your home policy renews on 1 September. Documents are in the portal.",
            account: CompanionAccounts.personal,
            mailbox: "Archive.mbox"
        ),
        Seed(
            name: "28.emlx",
            from: "you@personal.example",
            to: "Dentist <hello@practice.example>",
            subject: "Re: Appointment reminder",
            date: "Sun, 17 Aug 2026 12:20:00 +0000",
            body: "Confirmed for Thursday 08:20. Thanks.",
            account: CompanionAccounts.personal,
            mailbox: "Sent Messages.mbox"
        ),
        Seed(
            name: "29.emlx",
            from: "you@personal.example",
            to: "Landlord <lets@housing.example>",
            subject: "Re: Inspection next Tuesday",
            date: "Wed, 13 Aug 2026 12:02:00 +0000",
            body: "I will be home. Please use the side entrance.",
            account: CompanionAccounts.personal,
            mailbox: "Sent Messages.mbox"
        ),
        Seed(
            name: "30.emlx",
            from: "Newsletter <weekly@eng.example>",
            to: "you@company.com",
            subject: "This week in local mail",
            date: "Mon, 10 Aug 2026 07:00:00 +0000",
            body: "A roundup of on-device indexing, Full Disk Access, and companion shells.",
            account: CompanionAccounts.work,
            mailbox: "INBOX.mbox"
        ),
    ]

    private static func write(_ message: Seed, at root: URL) throws {
        try write(
            named: message.name,
            rfc822: """
            From: \(message.from)
            To: \(message.to)
            Subject: \(message.subject)
            Date: \(message.date)
            Content-Type: text/plain

            \(message.body)
            """,
            account: message.account,
            mailbox: message.mailbox,
            root: root
        )
    }

    private static func write(
        named name: String,
        rfc822: String,
        account: String,
        mailbox: String,
        root: URL
    ) throws {
        let messages = root
            .appendingPathComponent("V10", isDirectory: true)
            .appendingPathComponent(account, isDirectory: true)
            .appendingPathComponent(mailbox, isDirectory: true)
            .appendingPathComponent("Messages", isDirectory: true)
        try FileManager.default.createDirectory(at: messages, withIntermediateDirectories: true)
        let payload = Data(rfc822.utf8)
        var file = Data()
        file.append(Data("\(payload.count)\n".utf8))
        file.append(payload)
        file.append(Data("""

        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0">
        <dict>
        	<key>flags</key>
        	<integer>0</integer>
        </dict>
        </plist>
        """.utf8))
        try file.write(to: messages.appendingPathComponent(name))
    }
}
