import Foundation
import Testing
@testable import ClaudeUsageBar

struct UsageRowModelTests {
    private let formatter: ResetTimeFormatter
    private let now: Date

    init() throws {
        formatter = ResetTimeFormatter(timeZone: try #require(TimeZone(identifier: "Asia/Seoul")))
        // 한국 시간 2026-11-18(수) 19:25
        now = try Self.date("2026-11-18T10:25:00Z")
    }

    @Test func sessionRowShowsRelativeTime() throws {
        let model = try model(
            title: "현재 세션",
            json: #"{ "utilization": 21, "resets_at": "2026-11-18T12:40:00+00:00" }"#,
            showsRelativeTime: true
        )

        #expect(model.percentText == "21% 사용")
        #expect(model.progressValue == 21)
        #expect(model.tone == .normal)
        #expect(model.resetText == "초기화 · 오늘 21:40 (2시간 15분 후)")
        #expect(model.accessibilityLabel == "현재 세션 21퍼센트 사용, 오늘 오후 9시 40분 초기화")
    }

    @Test func weeklyRowOmitsRelativeTime() throws {
        let model = try model(
            title: "주간",
            json: #"{ "utilization": 85, "resets_at": "2026-11-21T00:00:00+00:00" }"#,
            showsRelativeTime: false
        )

        #expect(model.percentText == "85% 사용")
        #expect(model.progressValue == 85)
        #expect(model.tone == .warning)
        #expect(model.resetText == "초기화 · 11월 21일 (토) 09:00")
    }

    @Test func pastResetShowsWaitingStateEvenWithoutRelativeTime() throws {
        let model = try model(
            title: "주간",
            json: #"{ "utilization": 97, "resets_at": "2026-11-18T10:00:00+00:00" }"#,
            showsRelativeTime: false
        )

        #expect(model.tone == .critical)
        #expect(model.resetText == "초기화 · 오늘 19:00 (초기화됨 · 갱신 대기)")
        #expect(model.accessibilityLabel == "주간 97퍼센트 사용, 초기화됨, 갱신 대기")
    }

    @Test func noActiveSessionShowsNoUsage() throws {
        let model = try model(title: "현재 세션", json: "null", showsRelativeTime: true)

        #expect(model.percentText == "0% 사용")
        #expect(model.progressValue == 0)
        #expect(model.resetText == "세션 없음")
    }

    @Test func missingSnapshotShowsPlaceholder() {
        let model = UsageRowModel(
            title: "현재 세션",
            window: nil,
            showsRelativeTime: true,
            now: now,
            formatter: formatter
        )

        #expect(model.percentText == "–% 사용")
        #expect(model.progressValue == 0)
        #expect(model.resetText == "데이터 없음")
        #expect(model.accessibilityLabel == "현재 세션 사용량 알 수 없음, 데이터 없음")
    }

    @Test func invalidDateShowsUnknownReset() throws {
        let model = try model(
            title: "현재 세션",
            json: #"{ "utilization": 30, "resets_at": "not-a-date" }"#,
            showsRelativeTime: true
        )

        #expect(model.percentText == "30% 사용")
        #expect(model.resetText == "초기화 시간 알 수 없음")
    }

    @Test func failureBannersMatchSpecification() {
        #expect(RefreshFailure.authentication.bannerMessage
            == "Claude Code 로그인 정보를 읽을 수 없어요. 터미널에서 `claude`로 다시 로그인해 주세요.")
        #expect(RefreshFailure.temporary.bannerMessage == "업데이트가 지연되고 있어요. 마지막 값 표시 중.")
    }

    private func model(title: String, json: String, showsRelativeTime: Bool) throws -> UsageRowModel {
        let data = Data(#"{ "five_hour": \#(json) }"#.utf8)
        let snapshot = try UsageSnapshot.decode(from: data, fetchedAt: now)
        return UsageRowModel(
            title: title,
            window: snapshot.session,
            showsRelativeTime: showsRelativeTime,
            now: now,
            formatter: formatter
        )
    }

    private static func date(_ string: String) throws -> Date {
        try #require(UsageDateParser.date(from: string))
    }
}
