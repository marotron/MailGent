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

    private static func clock(_ date: Date) -> String {
        date.formatted(date: .omitted, time: .shortened)
    }

    @Test func windowCaptionSameDayIsRangeAndMinutes() {
        let now = Self.date(year: 2026, month: 8, day: 26, hour: 18, minute: 4)
        let start = Self.date(year: 2026, month: 8, day: 26, hour: 12, minute: 15)
        let end = Self.date(year: 2026, month: 8, day: 26, hour: 12, minute: 31)
        let label = CompanionStatusCopy.windowCaption(
            from: start,
            to: end,
            now: now,
            calendar: Self.london
        )
        #expect(label == "\(Self.clock(start))–\(Self.clock(end)) (16m)")
        #expect(!label.contains("since"))
        #expect(!label.contains("yesterday"))
    }

    @Test func windowCaptionUsesHoursAndMinutesWhenOverAnHour() {
        let now = Self.date(year: 2026, month: 8, day: 26, hour: 10, minute: 2)
        let start = Self.date(year: 2026, month: 8, day: 26, hour: 9, minute: 0)
        let end = Self.date(year: 2026, month: 8, day: 26, hour: 10, minute: 2)
        let label = CompanionStatusCopy.windowCaption(
            from: start,
            to: end,
            now: now,
            calendar: Self.london
        )
        #expect(label == "\(Self.clock(start))–\(Self.clock(end)) (1h 2m)")
    }

    @Test func windowCaptionNamesYesterdayWhenWindowWasYesterday() {
        let now = Self.date(year: 2026, month: 8, day: 26, hour: 10, minute: 2)
        let start = Self.date(year: 2026, month: 8, day: 25, hour: 15, minute: 48)
        let end = Self.date(year: 2026, month: 8, day: 25, hour: 16, minute: 4)
        let label = CompanionStatusCopy.windowCaption(
            from: start,
            to: end,
            now: now,
            calendar: Self.london
        )
        #expect(label == "yesterday \(Self.clock(start))–\(Self.clock(end)) (16m)")
        #expect(!label.contains("25"))
    }

    @Test func windowCaptionIncludesDateWhenOlderThanYesterday() {
        let now = Self.date(year: 2026, month: 8, day: 26, hour: 10, minute: 2)
        let start = Self.date(year: 2026, month: 8, day: 24, hour: 15, minute: 48)
        let end = Self.date(year: 2026, month: 8, day: 24, hour: 16, minute: 4)
        let label = CompanionStatusCopy.windowCaption(
            from: start,
            to: end,
            now: now,
            calendar: Self.london
        )
        #expect(label.hasSuffix("\(Self.clock(start))–\(Self.clock(end)) (16m)"))
        #expect(!label.contains("yesterday"))
        #expect(label.contains("24"))
    }

    @Test func windowCaptionSpansMidnightWithDayAwareEnds() {
        let now = Self.date(year: 2026, month: 8, day: 26, hour: 10, minute: 2)
        let start = Self.date(year: 2026, month: 8, day: 25, hour: 23, minute: 50)
        let end = Self.date(year: 2026, month: 8, day: 26, hour: 0, minute: 10)
        let label = CompanionStatusCopy.windowCaption(
            from: start,
            to: end,
            now: now,
            calendar: Self.london
        )
        #expect(label == "yesterday \(Self.clock(start))–\(Self.clock(end)) (20m)")
    }

    @Test func relativeAgeUsesHoursWithoutParentheses() {
        let now = Self.date(year: 2026, month: 8, day: 26, hour: 10, minute: 1)
        let ingest = Self.date(year: 2026, month: 8, day: 25, hour: 22, minute: 1)
        #expect(CompanionStatusCopy.relativeAge(from: ingest, to: now) == "12h ago")
    }
}
