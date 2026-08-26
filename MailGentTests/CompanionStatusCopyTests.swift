import Foundation
import Testing
@testable import MailGent

struct CompanionStatusCopyTests {
    private static var london: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/London")!
        return calendar
    }

    private static func date(
        year: Int,
        month: Int,
        day: Int,
        hour: Int,
        minute: Int
    ) -> Date {
        var components = DateComponents()
        components.year = year
        components.month = month
        components.day = day
        components.hour = hour
        components.minute = minute
        return Self.london.date(from: components)!
    }

    @Test func sinceCaptionKeepsClockWhenSameDay() {
        let now = Self.date(year: 2026, month: 8, day: 26, hour: 10, minute: 2)
        let since = Self.date(year: 2026, month: 8, day: 26, hour: 9, minute: 0)
        let label = CompanionStatusCopy.sinceCaption(from: since, now: now, calendar: Self.london)
        #expect(label.hasPrefix("since "))
        #expect(!label.contains("yesterday"))
        #expect(!label.contains("Aug"))
        #expect(!label.contains("2026"))
    }

    @Test func sinceCaptionNamesYesterday() {
        let now = Self.date(year: 2026, month: 8, day: 26, hour: 10, minute: 2)
        let since = Self.date(year: 2026, month: 8, day: 25, hour: 15, minute: 48)
        let label = CompanionStatusCopy.sinceCaption(from: since, now: now, calendar: Self.london)
        #expect(label.hasPrefix("since yesterday "))
        #expect(!label.contains("25"))
    }

    @Test func sinceCaptionIncludesDateWhenOlderThanYesterday() {
        let now = Self.date(year: 2026, month: 8, day: 26, hour: 10, minute: 2)
        let since = Self.date(year: 2026, month: 8, day: 24, hour: 15, minute: 48)
        let label = CompanionStatusCopy.sinceCaption(from: since, now: now, calendar: Self.london)
        #expect(label.hasPrefix("since "))
        #expect(!label.contains("yesterday"))
        #expect(label.contains("24"))
    }

    @Test func relativeAgeUsesHoursWithoutParentheses() {
        let now = Self.date(year: 2026, month: 8, day: 26, hour: 10, minute: 1)
        let ingest = Self.date(year: 2026, month: 8, day: 25, hour: 22, minute: 1)
        #expect(CompanionStatusCopy.relativeAge(from: ingest, to: now) == "12h ago")
    }
}
