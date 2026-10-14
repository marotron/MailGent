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
                plain: """
                Standup — wave \(n)

                Yesterday
                • Index work on Companion fixtures
                • Tightened Access Log filters

                Today
                • Ingest wave \(n)
                • Pair Cursor against the demo grant

                Blockers
                • None
                """,
                html: mailHTML("""
                <h2 style="margin:0 0 12px;font-size:16px;">Standup — wave \(n)</h2>
                <p style="margin:0 0 8px;"><strong>Yesterday</strong></p>
                <ul style="margin:0 0 12px;padding-left:18px;">
                  <li>Index work on Companion fixtures</li>
                  <li>Tightened Access Log filters</li>
                </ul>
                <p style="margin:0 0 8px;"><strong>Today</strong></p>
                <ul style="margin:0 0 12px;padding-left:18px;">
                  <li>Ingest wave \(n)</li>
                  <li>Pair Cursor against the demo grant</li>
                </ul>
                <p style="margin:0;color:#6e6e73;"><strong>Blockers:</strong> none</p>
                """),
                account: CompanionAccounts.work,
                mailbox: "INBOX.mbox"
            ),
            Seed(
                name: "w\(wave)-b.emlx",
                from: "CI <ci@company.com>",
                to: "you@company.com",
                subject: "Build \(n) passed",
                date: "Wed, 19 Aug 2026 09:2\(wave % 10):00 +0000",
                plain: """
                ✓ mailgent-macos #\(40 + wave) is green on arm64.

                Job: release-smoke
                Branch: main
                Duration: 4m 12s

                Artifacts: MailGent-\(n).0.0.dmg (unsigned demo)
                """,
                html: mailHTML("""
                <p style="margin:0 0 12px;color:#1a7f37;font-weight:600;">✓ mailgent-macos #\((40 + wave)) is green on arm64.</p>
                <table style="border-collapse:collapse;font-size:13px;">
                  <tr><td style="padding:2px 12px 2px 0;color:#6e6e73;">Job</td><td>release-smoke</td></tr>
                  <tr><td style="padding:2px 12px 2px 0;color:#6e6e73;">Branch</td><td>main</td></tr>
                  <tr><td style="padding:2px 12px 2px 0;color:#6e6e73;">Duration</td><td>4m 12s</td></tr>
                </table>
                <p style="margin:12px 0 0;font-size:13px;">Artifacts: <code>MailGent-\(n).0.0.dmg</code> (unsigned demo)</p>
                """),
                account: CompanionAccounts.work,
                mailbox: "INBOX.mbox"
            ),
            Seed(
                name: "w\(wave)-c.emlx",
                from: "Calendar <calendar@company.com>",
                to: "you@company.com",
                subject: "Reminder: 1:1 in 15 minutes",
                date: "Wed, 19 Aug 2026 10:0\(wave % 10):00 +0000",
                plain: """
                1:1 with Ava Chen starts in 15 minutes.

                When: today, 15 minutes from now
                Where: Meet link in calendar
                Agenda: wave \(n) ingest + screenshot pass
                """,
                html: calendarHTML(
                    title: "1:1 with Ava Chen",
                    when: "Starts in 15 minutes",
                    location: "Meet link in calendar",
                    note: "Agenda: wave \(n) ingest + screenshot pass"
                ),
                account: CompanionAccounts.work,
                mailbox: "INBOX.mbox"
            ),
            Seed(
                name: "w\(wave)-d.emlx",
                from: "Receipts <receipts@personal.example>",
                to: "you@personal.example",
                subject: "Order \(1200 + wave) confirmed",
                date: "Wed, 19 Aug 2026 11:4\(wave % 10):00 +0000",
                plain: """
                Thanks — order #\(1200 + wave) is confirmed.

                Items ship tomorrow.
                Total: £24.90
                Account: DEMO-01
                """,
                html: receiptHTML(
                    title: "Order confirmed",
                    order: "\(1200 + wave)",
                    rows: [
                        ("Items", "Notebook set ×1"),
                        ("Ship", "Tomorrow"),
                        ("Total", "£24.90"),
                        ("Account", "DEMO-01"),
                    ],
                    footer: "Wave \(n) demo receipt — fake data only."
                ),
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
        /// Plain text part (and sole body when `html` is nil).
        var plain: String
        /// When set, message is `multipart/alternative` with plain + HTML.
        var html: String? = nil
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
            plain: """
            Hi —

            Here is the revised schedule and proposed next steps for quarterly planning.

            1. Lock themes by Friday
            2. Draft OKRs with Jordan
            3. Share the deck before Tuesday’s review

            Happy to jam on slide 7 if the August snapshot is ready.

            — Ava
            """,
            html: mailHTML("""
            <p>Hi —</p>
            <p>Here is the revised schedule and proposed next steps for quarterly planning.</p>
            <ol>
              <li>Lock themes by Friday</li>
              <li>Draft OKRs with Jordan</li>
              <li>Share the deck before Tuesday’s review</li>
            </ol>
            <p>Happy to jam on slide 7 if the August snapshot is ready.</p>
            <p style="color:#6e6e73;">— Ava</p>
            """),
            account: CompanionAccounts.work,
            mailbox: "INBOX.mbox"
        ),
        Seed(
            name: "2.emlx",
            from: "Product team <product@company.com>",
            to: "you@company.com",
            subject: "Planning workshop follow-up",
            date: "Fri, 16 Aug 2024 16:05:00 +0000",
            plain: """
            Thanks for joining.

            Notes and actions from the planning workshop are in the shared doc.
            Owners are tagged; please update status before Monday standup.
            """,
            html: mailHTML("""
            <p>Thanks for joining.</p>
            <p>Notes and actions from the planning workshop are in the
            <a href="https://docs.example/company/planning-workshop">shared doc</a>.</p>
            <p>Owners are tagged; please update status before Monday standup.</p>
            """),
            account: CompanionAccounts.work,
            mailbox: "INBOX.mbox"
        ),
        Seed(
            name: "3.emlx",
            from: "you@company.com",
            to: "Ava Chen <ava@company.com>",
            subject: "Re: Q3 planning notes",
            date: "Mon, 19 Aug 2024 11:04:00 +0000",
            plain: "Confirmed for Tuesday. I will send the planning deck before noon.",
            account: CompanionAccounts.work,
            mailbox: "Sent Messages.mbox"
        ),
        Seed(
            name: "4.emlx",
            from: "Marcus Ltd. <statements@marcus.example>",
            to: "you@personal.example",
            subject: "Quarterly statement ready",
            date: "Sun, 18 Aug 2024 09:12:00 +0000",
            plain: """
            Your new statement is ready to review in the portal.

            Account: DEMO-01
            Period: Apr–Jun 2024
            Balance: £1,240.55
            """,
            html: receiptHTML(
                title: "Quarterly statement ready",
                order: "STMT-2024-Q2",
                rows: [
                    ("Account", "DEMO-01"),
                    ("Period", "Apr–Jun 2024"),
                    ("Balance", "£1,240.55"),
                ],
                footer: "Open the portal to download a PDF. Demo data only."
            ),
            account: CompanionAccounts.personal,
            mailbox: "INBOX.mbox"
        ),
        // Incomplete download stub — keep plain; Companion marks `.partial.emlx`.
        Seed(
            name: "7.partial.emlx",
            from: "Photos <photos@personal.example>",
            to: "you@personal.example",
            subject: "Download remaining",
            date: "Sat, 17 Aug 2024 14:20:00 +0000",
            plain: "has stub",
            account: CompanionAccounts.personal,
            mailbox: "INBOX.mbox"
        ),
        // Empty body edge case.
        Seed(
            name: "8.emlx",
            from: "Receipts <receipts@personal.example>",
            to: "you@personal.example",
            subject: "Empty receipt",
            date: "Thu, 15 Aug 2024 08:00:00 +0000",
            plain: "",
            account: CompanionAccounts.personal,
            mailbox: "Archive.mbox"
        ),
        Seed(
            name: "10.emlx",
            from: "Jordan Lee <jordan@company.com>",
            to: "you@company.com",
            subject: "Design review Thursday",
            date: "Tue, 18 Aug 2026 09:15:00 +0000",
            plain: """
            Can we move design review to 15:00?

            I will share the Figma link before lunch. Prototype screenshots can land in the review doc.
            """,
            html: mailHTML("""
            <p>Can we move design review to <strong>15:00</strong>?</p>
            <p>I will share the Figma link before lunch. Prototype screenshots can land in the review doc.</p>
            """),
            account: CompanionAccounts.work,
            mailbox: "INBOX.mbox"
        ),
        Seed(
            name: "11.emlx",
            from: "IT Security <security@company.com>",
            to: "you@company.com",
            subject: "VPN certificate expires Friday",
            date: "Mon, 17 Aug 2026 07:40:00 +0000",
            plain: """
            Renew the office VPN cert before Friday or you will be locked out of staging.

            Host: vpn.company.com
            Expires: Friday 17:00 UTC
            Runbook: https://docs.example/company/vpn-renew
            """,
            html: mailHTML("""
            <p style="margin:0 0 12px;padding:10px 12px;background:#fff4e5;border-left:3px solid #f5a623;">
              Renew the office VPN cert before Friday or you will be locked out of staging.
            </p>
            <table style="border-collapse:collapse;font-size:13px;">
              <tr><td style="padding:2px 12px 2px 0;color:#6e6e73;">Host</td><td><code>vpn.company.com</code></td></tr>
              <tr><td style="padding:2px 12px 2px 0;color:#6e6e73;">Expires</td><td>Friday 17:00 UTC</td></tr>
            </table>
            <p style="margin:12px 0 0;"><a href="https://docs.example/company/vpn-renew">Open runbook</a></p>
            """),
            account: CompanionAccounts.work,
            mailbox: "INBOX.mbox"
        ),
        Seed(
            name: "12.emlx",
            from: "Hiring <hiring@company.com>",
            to: "you@company.com",
            subject: "Interview loop: Maya Patel",
            date: "Sun, 16 Aug 2026 19:22:00 +0000",
            plain: """
            Maya is on-site Wednesday.

            Please take the systems interview slot at 11:00.
            Scorecard template is attached in the hiring folder.
            """,
            html: mailHTML("""
            <p><strong>Maya Patel</strong> is on-site Wednesday.</p>
            <p>Please take the systems interview slot at <strong>11:00</strong>.</p>
            <p style="color:#6e6e73;font-size:13px;">Scorecard template is in the hiring folder.</p>
            """),
            account: CompanionAccounts.work,
            mailbox: "INBOX.mbox"
        ),
        Seed(
            name: "13.emlx",
            from: "Legal <legal@company.com>",
            to: "you@company.com",
            subject: "DPA for MailGent vendors",
            date: "Fri, 14 Aug 2026 13:05:00 +0000",
            plain: """
            Please confirm the data processing addendum before we enable the new vendor.

            Doc: https://docs.example/company/dpa-mailgent
            Need: sign-off or questions by EOD Friday.
            """,
            html: mailHTML("""
            <p>Please confirm the data processing addendum before we enable the new vendor.</p>
            <p><a href="https://docs.example/company/dpa-mailgent">Open DPA draft</a></p>
            <p style="color:#6e6e73;font-size:13px;">Need: sign-off or questions by EOD Friday.</p>
            """),
            account: CompanionAccounts.work,
            mailbox: "INBOX.mbox"
        ),
        Seed(
            name: "14.emlx",
            from: "Office <office@company.com>",
            to: "you@company.com",
            subject: "Desk booking next week",
            date: "Thu, 13 Aug 2026 16:48:00 +0000",
            plain: """
            Tuesday and Thursday are already at capacity.

            Book a desk if you plan to come in:
            https://office.example/desks
            """,
            html: mailHTML("""
            <p>Tuesday and Thursday are already at capacity.</p>
            <p><a href="https://office.example/desks">Book a desk</a> if you plan to come in.</p>
            """),
            account: CompanionAccounts.work,
            mailbox: "INBOX.mbox"
        ),
        Seed(
            name: "15.emlx",
            from: "Ava Chen <ava@company.com>",
            to: "you@company.com",
            subject: "Re: planning deck",
            date: "Wed, 12 Aug 2026 18:11:00 +0000",
            plain: "Slide 7 still has last quarter’s numbers. Can you swap in the August snapshot?",
            html: mailHTML("""
            <p>Slide 7 still has last quarter’s numbers. Can you swap in the August snapshot?</p>
            """),
            account: CompanionAccounts.work,
            mailbox: "INBOX.mbox"
        ),
        Seed(
            name: "16.emlx",
            from: "Support <support@company.com>",
            to: "you@company.com",
            subject: "Customer asked about export",
            date: "Tue, 11 Aug 2026 10:03:00 +0000",
            plain: """
            Acme wants a mailbox export for their legal hold.

            Is that in scope for local-read, or do we point them at Apple Mail export?
            Contact on the ticket: alex@example.com
            """,
            html: mailHTML("""
            <p><strong>Acme</strong> wants a mailbox export for their legal hold.</p>
            <p>Is that in scope for local-read, or do we point them at Apple Mail export?</p>
            <p style="font-size:13px;color:#6e6e73;">Contact on the ticket: alex@example.com</p>
            """),
            account: CompanionAccounts.work,
            mailbox: "INBOX.mbox"
        ),
        Seed(
            name: "17.emlx",
            from: "you@company.com",
            to: "Jordan Lee <jordan@company.com>",
            subject: "Re: Design review Thursday",
            date: "Tue, 18 Aug 2026 09:40:00 +0000",
            plain: "15:00 works. I will add the prototype screenshots to the review doc.",
            account: CompanionAccounts.work,
            mailbox: "Sent Messages.mbox"
        ),
        Seed(
            name: "18.emlx",
            from: "you@company.com",
            to: "Hiring <hiring@company.com>",
            subject: "Re: Interview loop: Maya Patel",
            date: "Sun, 16 Aug 2026 20:01:00 +0000",
            plain: "Booked. Sending a scorecard template this evening.",
            account: CompanionAccounts.work,
            mailbox: "Sent Messages.mbox"
        ),
        Seed(
            name: "19.emlx",
            from: "you@company.com",
            to: "Legal <legal@company.com>",
            subject: "Re: DPA for MailGent vendors",
            date: "Fri, 14 Aug 2026 15:22:00 +0000",
            plain: "Reviewed. One question on subprocessors — see comments in the doc.",
            account: CompanionAccounts.work,
            mailbox: "Sent Messages.mbox"
        ),
        Seed(
            name: "20.emlx",
            from: "School <office@school.example>",
            to: "you@personal.example",
            subject: "Inset day 4 September",
            date: "Mon, 18 Aug 2026 08:30:00 +0000",
            plain: """
            School is closed for staff training on 4 September.

            Wraparound care is unavailable that day.
            """,
            html: mailHTML("""
            <p>School is closed for staff training on <strong>4 September</strong>.</p>
            <p>Wraparound care is unavailable that day.</p>
            """),
            account: CompanionAccounts.personal,
            mailbox: "INBOX.mbox"
        ),
        Seed(
            name: "21.emlx",
            from: "Dentist <hello@practice.example>",
            to: "you@personal.example",
            subject: "Appointment reminder",
            date: "Sun, 17 Aug 2026 12:00:00 +0000",
            plain: """
            Your checkup is Thursday at 08:20.

            Reply CANCEL if you need to move it.
            Practice: Riverside Dental
            """,
            html: calendarHTML(
                title: "Dental checkup",
                when: "Thursday 08:20",
                location: "Riverside Dental",
                note: "Reply CANCEL if you need to move it."
            ),
            account: CompanionAccounts.personal,
            mailbox: "INBOX.mbox"
        ),
        Seed(
            name: "22.emlx",
            from: "Council <noreply@city.example>",
            to: "you@personal.example",
            subject: "Bin collection moved",
            date: "Sat, 16 Aug 2026 06:12:00 +0000",
            plain: """
            Garden waste moves to Friday this week because of the bank holiday.

            Address: 12 Demo Street
            Usual day: Thursday → this week: Friday
            """,
            html: mailHTML("""
            <p>Garden waste moves to <strong>Friday</strong> this week because of the bank holiday.</p>
            <table style="border-collapse:collapse;font-size:13px;">
              <tr><td style="padding:2px 12px 2px 0;color:#6e6e73;">Address</td><td>12 Demo Street</td></tr>
              <tr><td style="padding:2px 12px 2px 0;color:#6e6e73;">Usual day</td><td>Thursday</td></tr>
              <tr><td style="padding:2px 12px 2px 0;color:#6e6e73;">This week</td><td>Friday</td></tr>
            </table>
            """),
            account: CompanionAccounts.personal,
            mailbox: "INBOX.mbox"
        ),
        Seed(
            name: "23.emlx",
            from: "Bank <alerts@bank.example>",
            to: "you@personal.example",
            subject: "New login from Safari",
            date: "Fri, 15 Aug 2026 21:44:00 +0000",
            plain: """
            We noticed a new sign-in. If this was you, no action needed.

            Device: Safari on macOS
            Approximate location: Edinburgh, UK
            Time: Fri 15 Aug 2026 21:44 UTC
            Account: ****DEMO
            """,
            html: alertHTML(
                title: "New login from Safari",
                body: "We noticed a new sign-in. If this was you, no action needed.",
                rows: [
                    ("Device", "Safari on macOS"),
                    ("Location", "Edinburgh, UK"),
                    ("Time", "Fri 15 Aug 2026 21:44 UTC"),
                    ("Account", "****DEMO"),
                ]
            ),
            account: CompanionAccounts.personal,
            mailbox: "INBOX.mbox"
        ),
        Seed(
            name: "24.emlx",
            from: "Flights <trips@airline.example>",
            to: "you@personal.example",
            subject: "Boarding pass: EDI → LHR",
            date: "Thu, 14 Aug 2026 05:55:00 +0000",
            plain: """
            Check-in is open.

            Flight: BA1234
            Route: EDI → LHR
            Seat: 14A
            Gate: published 90 minutes before departure
            Passenger: Alex Demo
            """,
            html: boardingHTML(
                flight: "BA1234",
                route: "EDI → LHR",
                seat: "14A",
                passenger: "Alex Demo"
            ),
            account: CompanionAccounts.personal,
            mailbox: "INBOX.mbox"
        ),
        Seed(
            name: "25.emlx",
            from: "Landlord <lets@housing.example>",
            to: "you@personal.example",
            subject: "Inspection next Tuesday",
            date: "Wed, 13 Aug 2026 11:17:00 +0000",
            plain: """
            Annual inspection between 10:00 and 12:00.

            Someone 18+ must be home.
            Address: 12 Demo Street
            """,
            html: mailHTML("""
            <p>Annual inspection between <strong>10:00 and 12:00</strong> next Tuesday.</p>
            <p>Someone 18+ must be home.</p>
            <p style="font-size:13px;color:#6e6e73;">Address: 12 Demo Street</p>
            """),
            account: CompanionAccounts.personal,
            mailbox: "INBOX.mbox"
        ),
        Seed(
            name: "26.emlx",
            from: "Bookstore <orders@books.example>",
            to: "you@personal.example",
            subject: "Your order has shipped",
            date: "Tue, 12 Aug 2026 14:09:00 +0000",
            plain: """
            Tracking is live. Estimated delivery Thursday.

            Order: BK-88421
            Carrier: Demo Post
            Tracking: DP000123456GB
            """,
            html: receiptHTML(
                title: "Your order has shipped",
                order: "BK-88421",
                rows: [
                    ("Carrier", "Demo Post"),
                    ("Tracking", "DP000123456GB"),
                    ("ETA", "Thursday"),
                ],
                footer: "Track parcel: https://track.example/DP000123456GB"
            ),
            account: CompanionAccounts.personal,
            mailbox: "Archive.mbox"
        ),
        Seed(
            name: "27.emlx",
            from: "Insurance <claims@cover.example>",
            to: "you@personal.example",
            subject: "Policy renewal",
            date: "Mon, 11 Aug 2026 09:00:00 +0000",
            plain: """
            Your home policy renews on 1 September.

            Policy: HOME-DEMO-01
            Premium: £312.00 / year
            Documents are in the portal.
            """,
            html: receiptHTML(
                title: "Policy renewal",
                order: "HOME-DEMO-01",
                rows: [
                    ("Renews", "1 September"),
                    ("Premium", "£312.00 / year"),
                ],
                footer: "Documents are in the portal. Demo data only."
            ),
            account: CompanionAccounts.personal,
            mailbox: "Archive.mbox"
        ),
        Seed(
            name: "28.emlx",
            from: "you@personal.example",
            to: "Dentist <hello@practice.example>",
            subject: "Re: Appointment reminder",
            date: "Sun, 17 Aug 2026 12:20:00 +0000",
            plain: "Confirmed for Thursday 08:20. Thanks.",
            account: CompanionAccounts.personal,
            mailbox: "Sent Messages.mbox"
        ),
        Seed(
            name: "29.emlx",
            from: "you@personal.example",
            to: "Landlord <lets@housing.example>",
            subject: "Re: Inspection next Tuesday",
            date: "Wed, 13 Aug 2026 12:02:00 +0000",
            plain: "I will be home. Please use the side entrance.",
            account: CompanionAccounts.personal,
            mailbox: "Sent Messages.mbox"
        ),
        Seed(
            name: "30.emlx",
            from: "Newsletter <weekly@eng.example>",
            to: "you@company.com",
            subject: "This week in local mail",
            date: "Mon, 10 Aug 2026 07:00:00 +0000",
            plain: """
            A roundup of on-device indexing, Full Disk Access, and companion shells.

            • Fixture HTML multipart bodies for Companion Read
            • Traffic-sign Pass / Block marks
            • Screenshot recipe for version closeout

            Unsubscribe: https://eng.example/unsub/demo
            """,
            html: newsletterHTML(
                title: "This week in local mail",
                intro: "A roundup of on-device indexing, Full Disk Access, and companion shells.",
                items: [
                    "Fixture HTML multipart bodies for Companion Read",
                    "Traffic-sign Pass / Block marks",
                    "Screenshot recipe for version closeout",
                ],
                unsub: "https://eng.example/unsub/demo"
            ),
            account: CompanionAccounts.work,
            mailbox: "INBOX.mbox"
        ),
    ]

    // MARK: - HTML templates (demo-safe)

    private static func mailHTML(_ blocks: String) -> String {
        """
        <!doctype html>
        <html><head><meta charset="utf-8"></head>
        <body style="margin:0;padding:16px;background:#ffffff;font-family:-apple-system,BlinkMacSystemFont,Helvetica,Arial,sans-serif;font-size:14px;line-height:1.45;color:#1d1d1f;">
        \(blocks)
        </body></html>
        """
    }

    private static func calendarHTML(title: String, when: String, location: String, note: String) -> String {
        mailHTML("""
        <div style="border:1px solid #d2d2d7;border-radius:10px;overflow:hidden;max-width:420px;">
          <div style="background:#005EA5;color:#fff;padding:12px 14px;font-weight:600;">\(title)</div>
          <div style="padding:14px;">
            <p style="margin:0 0 8px;"><span style="color:#6e6e73;">When</span><br>\(when)</p>
            <p style="margin:0 0 8px;"><span style="color:#6e6e73;">Where</span><br>\(location)</p>
            <p style="margin:0;color:#6e6e73;font-size:13px;">\(note)</p>
          </div>
        </div>
        """)
    }

    private static func receiptHTML(
        title: String,
        order: String,
        rows: [(String, String)],
        footer: String
    ) -> String {
        let rowHTML = rows.map { key, value in
            """
            <tr>
              <td style="padding:6px 0;color:#6e6e73;width:40%;">\(key)</td>
              <td style="padding:6px 0;font-weight:500;">\(value)</td>
            </tr>
            """
        }.joined()
        return mailHTML("""
        <div style="max-width:440px;">
          <h2 style="margin:0 0 4px;font-size:18px;">\(title)</h2>
          <p style="margin:0 0 14px;color:#6e6e73;font-size:13px;">Ref \(order)</p>
          <table style="width:100%;border-collapse:collapse;border-top:1px solid #e5e5ea;border-bottom:1px solid #e5e5ea;">
            \(rowHTML)
          </table>
          <p style="margin:14px 0 0;font-size:12px;color:#6e6e73;">\(footer)</p>
        </div>
        """)
    }

    private static func alertHTML(title: String, body: String, rows: [(String, String)]) -> String {
        let rowHTML = rows.map { key, value in
            """
            <tr>
              <td style="padding:4px 12px 4px 0;color:#6e6e73;">\(key)</td>
              <td style="padding:4px 0;">\(value)</td>
            </tr>
            """
        }.joined()
        return mailHTML("""
        <div style="max-width:440px;border-left:4px solid #C8102E;padding:4px 0 4px 14px;">
          <h2 style="margin:0 0 8px;font-size:16px;">\(title)</h2>
          <p style="margin:0 0 12px;">\(body)</p>
          <table style="border-collapse:collapse;font-size:13px;">\(rowHTML)</table>
        </div>
        """)
    }

    private static func boardingHTML(flight: String, route: String, seat: String, passenger: String) -> String {
        mailHTML("""
        <div style="max-width:420px;border-radius:12px;overflow:hidden;border:1px solid #d2d2d7;">
          <div style="background:#1d1d1f;color:#fff;padding:14px 16px;">
            <div style="font-size:12px;letter-spacing:0.08em;text-transform:uppercase;opacity:0.7;">Boarding pass</div>
            <div style="font-size:22px;font-weight:700;margin-top:4px;">\(route)</div>
          </div>
          <div style="padding:14px 16px;background:#f5f5f7;">
            <table style="width:100%;border-collapse:collapse;font-size:13px;">
              <tr><td style="padding:4px 0;color:#6e6e73;">Flight</td><td style="padding:4px 0;font-weight:600;">\(flight)</td></tr>
              <tr><td style="padding:4px 0;color:#6e6e73;">Seat</td><td style="padding:4px 0;font-weight:600;">\(seat)</td></tr>
              <tr><td style="padding:4px 0;color:#6e6e73;">Passenger</td><td style="padding:4px 0;">\(passenger)</td></tr>
              <tr><td style="padding:4px 0;color:#6e6e73;">Gate</td><td style="padding:4px 0;">Published 90 min before departure</td></tr>
            </table>
          </div>
        </div>
        """)
    }

    private static func newsletterHTML(title: String, intro: String, items: [String], unsub: String) -> String {
        let list = items.map { "<li style=\"margin:0 0 6px;\">\($0)</li>" }.joined()
        return mailHTML("""
        <div style="max-width:480px;">
          <div style="font-size:11px;letter-spacing:0.1em;text-transform:uppercase;color:#6e6e73;margin-bottom:8px;">Engineering weekly</div>
          <h1 style="margin:0 0 12px;font-size:22px;">\(title)</h1>
          <p style="margin:0 0 14px;">\(intro)</p>
          <ul style="margin:0 0 16px;padding-left:18px;">\(list)</ul>
          <p style="margin:0;font-size:12px;color:#6e6e73;">
            <a href="\(unsub)" style="color:#6e6e73;">Unsubscribe</a>
          </p>
        </div>
        """)
    }

    // MARK: - Write

    private static func write(_ message: Seed, at root: URL) throws {
        let stem = message.name
            .replacingOccurrences(of: ".partial.emlx", with: "")
            .replacingOccurrences(of: ".emlx", with: "")
        let messageID = "<\(stem).\(message.account.prefix(8))@companion.mailgent.local>"
        let rfc822: String
        if let html = message.html {
            let boundary = "MailGent=_fix_\(stem)"
            rfc822 = """
            From: \(message.from)
            To: \(message.to)
            Subject: \(message.subject)
            Date: \(message.date)
            Message-ID: \(messageID)
            MIME-Version: 1.0
            Content-Type: multipart/alternative; boundary="\(boundary)"

            --\(boundary)
            Content-Type: text/plain; charset=utf-8

            \(message.plain)
            --\(boundary)
            Content-Type: text/html; charset=utf-8

            \(html)
            --\(boundary)--
            """
        } else {
            rfc822 = """
            From: \(message.from)
            To: \(message.to)
            Subject: \(message.subject)
            Date: \(message.date)
            Message-ID: \(messageID)
            MIME-Version: 1.0
            Content-Type: text/plain; charset=utf-8

            \(message.plain)
            """
        }
        try write(
            named: message.name,
            rfc822: rfc822,
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
