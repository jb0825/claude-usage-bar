import Foundation
import Testing
@testable import ClaudeUsageBar

struct ResetTimeFormatterTests {
    private let formatter: ResetTimeFormatter
    private let now: Date

    init() throws {
        let seoul = try #require(TimeZone(identifier: "Asia/Seoul"))
        formatter = ResetTimeFormatter(timeZone: seoul)
        // 한국 시간 2026-11-18(수) 19:00
        now = try Self.date("2026-11-18T10:00:00Z")
    }

    @Test(arguments: [
        ("2026-11-18T12:40:00Z", "오늘 21:40"),
        ("2026-11-18T14:59:00Z", "오늘 23:59"),
        ("2026-11-18T15:00:00Z", "내일 00:00"),
        ("2026-11-19T00:00:00Z", "내일 09:00"),
        ("2026-11-19T15:00:00Z", "11월 20일 (금) 00:00"),
        ("2026-11-21T00:00:00Z", "11월 21일 (토) 09:00"),
    ])
    func formatsAbsoluteDate(resetsAt: String, expected: String) throws {
        let date = try Self.date(resetsAt)

        #expect(formatter.absoluteString(for: date, now: now) == expected)
    }

    @Test(arguments: [
        (8_100.0, "(2시간 15분 후)"),
        (8_159.0, "(2시간 15분 후)"),
        (7_200.0, "(2시간 후)"),
        (900.0, "(15분 후)"),
        (60.0, "(1분 후)"),
        (59.0, "(곧)"),
        (1.0, "(곧)"),
        (0.0, "(초기화됨 · 갱신 대기)"),
        (-60.0, "(초기화됨 · 갱신 대기)"),
    ])
    func formatsRelativeTime(secondsFromNow: Double, expected: String) {
        let date = now.addingTimeInterval(secondsFromNow)

        #expect(formatter.relativeString(for: date, now: now) == expected)
    }

    @Test(arguments: [
        ("2026-11-18T12:40:00Z", "오늘 오후 9시 40분"),
        ("2026-11-19T00:00:00Z", "내일 오전 9시"),
        ("2026-11-21T00:05:00Z", "11월 21일 토요일 오전 9시 5분"),
    ])
    func formatsAccessibilityDate(resetsAt: String, expected: String) throws {
        let date = try Self.date(resetsAt)

        #expect(formatter.accessibilityString(for: date, now: now) == expected)
    }

    @Test func formatsLastUpdatedTime() throws {
        let date = try Self.date("2026-11-18T08:24:00Z")

        #expect(formatter.timeString(for: date) == "17:24")
    }

    private static func date(_ string: String) throws -> Date {
        try #require(UsageDateParser.date(from: string))
    }
}
