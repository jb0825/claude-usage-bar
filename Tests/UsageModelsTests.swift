import Foundation
import Testing
@testable import ClaudeUsageBar

private final class FixtureBundleToken {}

struct UsageModelsTests {
    private let fetchedAt = Date(timeIntervalSince1970: 1_795_000_000)

    @Test func decodesNormalResponse() throws {
        let snapshot = try snapshot(fixture: "usage-normal")

        #expect(snapshot.session == UsageWindow.expected(21, "2026-11-18T12:40:00Z"))
        #expect(snapshot.weekly == UsageWindow.expected(74, "2026-11-21T00:00:00Z"))
        #expect(snapshot.fetchedAt == fetchedAt)
    }

    @Test func decodesRealSample() throws {
        let snapshot = try snapshot(fixture: "real-sample")

        #expect(snapshot.session == UsageWindow.expected(10, "2026-11-18T13:20:00Z"))
        #expect(snapshot.weekly == UsageWindow.expected(64, "2026-11-21T06:00:00Z"))
    }

    @Test func nullWindowOrNullResetMeansNoActiveSession() throws {
        let snapshot = try snapshot(fixture: "usage-null-session")

        #expect(snapshot.session.usedPercent == 0)
        #expect(snapshot.session.reset == .noActiveSession)
        #expect(snapshot.weekly.usedPercent == 0)
        #expect(snapshot.weekly.reset == .noActiveSession)
    }

    @Test func ignoresUnknownKeys() throws {
        let snapshot = try snapshot(fixture: "usage-unknown-keys")

        #expect(snapshot.session == UsageWindow.expected(40, "2026-11-18T12:40:00Z"))
        #expect(snapshot.weekly == UsageWindow.expected(50, "2026-11-21T00:00:00Z"))
    }

    @Test func invalidDateKeepsUsageValue() throws {
        let snapshot = try snapshot(fixture: "usage-invalid-date")

        #expect(snapshot.session.usedPercent == 30)
        #expect(snapshot.session.reset == .unknown)
        #expect(snapshot.weekly.usedPercent == 60)
        #expect(snapshot.weekly.reset == .unknown)
    }

    @Test(arguments: [
        (-5.0, 0),
        (0.0, 0),
        (20.5, 21),
        (20.4, 20),
        (20.6, 21),
        (100.0, 100),
        (120.0, 100),
    ])
    func clampsAndRoundsUsedPercent(utilization: Double, expected: Int) throws {
        let json = """
        { "five_hour": { "utilization": \(utilization), "resets_at": "2026-11-18T12:40:00+00:00" } }
        """

        let snapshot = try UsageSnapshot.decode(from: Data(json.utf8), fetchedAt: fetchedAt)

        #expect(snapshot.session.usedPercent == expected)
    }

    @Test func wrongFieldTypeDoesNotFailWholeResponse() throws {
        let json = """
        {
          "five_hour": { "utilization": "high", "resets_at": "2026-11-18T12:40:00+00:00" },
          "seven_day": "unexpected"
        }
        """

        let snapshot = try UsageSnapshot.decode(from: Data(json.utf8), fetchedAt: fetchedAt)

        #expect(snapshot.session.usedPercent == nil)
        #expect(snapshot.session.reset == .at(try date("2026-11-18T12:40:00Z")))
        #expect(snapshot.weekly.reset == .noActiveSession)
    }

    @Test func fractionalSecondJitterDoesNotChangeWindow() throws {
        let first = try window(resetsAt: "2026-11-18T13:20:00.467036+00:00")
        let second = try window(resetsAt: "2026-11-18T13:20:00.318905+00:00")

        #expect(first == second)
    }

    @Test func nonObjectResponseThrows() {
        #expect(throws: DecodingError.self) {
            try UsageSnapshot.decode(from: Data("[]".utf8), fetchedAt: fetchedAt)
        }
    }

    private func snapshot(fixture name: String) throws -> UsageSnapshot {
        let bundle = Bundle(for: FixtureBundleToken.self)
        let url = try #require(bundle.url(forResource: name, withExtension: "json"))
        return try UsageSnapshot.decode(from: Data(contentsOf: url), fetchedAt: fetchedAt)
    }

    private func window(resetsAt: String) throws -> UsageWindow {
        let json = """
        { "five_hour": { "utilization": 10, "resets_at": "\(resetsAt)" } }
        """
        return try UsageSnapshot.decode(from: Data(json.utf8), fetchedAt: fetchedAt).session
    }

    private func date(_ string: String) throws -> Date {
        try #require(UsageDateParser.date(from: string))
    }
}

private extension UsageWindow {
    static func expected(_ used: Int, _ resetsAt: String) -> ExpectedWindow {
        ExpectedWindow(used: used, resetsAt: UsageDateParser.date(from: resetsAt))
    }

    static func == (window: UsageWindow, expected: ExpectedWindow) -> Bool {
        guard let date = expected.resetsAt else { return false }
        return window.usedPercent == expected.used && window.reset == .at(date)
    }
}

private struct ExpectedWindow {
    let used: Int
    let resetsAt: Date?
}
