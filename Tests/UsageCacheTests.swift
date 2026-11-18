import Foundation
import Testing
@testable import ClaudeUsageBar

@MainActor
struct UsageCacheTests {
    private let suiteName = "com.claudeusagebar.tests.\(UUID().uuidString)"

    @Test func savedStateRoundTrips() throws {
        try withDefaults { defaults in
            let cache = UserDefaultsUsageCache(defaults: defaults)
            let state = PersistedUsageState(
                snapshot: try TestData.snapshot(fetchedAt: Date(timeIntervalSince1970: 100)),
                lastAttemptAt: Date(timeIntervalSince1970: 200)
            )

            cache.save(state)

            #expect(cache.load() == state)
        }
    }

    @Test func missingStateLoadsNil() throws {
        try withDefaults { defaults in
            #expect(UserDefaultsUsageCache(defaults: defaults).load() == nil)
        }
    }

    @Test func corruptedStateLoadsNil() throws {
        try withDefaults { defaults in
            defaults.set(Data("broken".utf8), forKey: Constants.Cache.usageStateKey)

            #expect(UserDefaultsUsageCache(defaults: defaults).load() == nil)
        }
    }

    @Test func expiredWindowLosesUsageButKeepsResetTime() throws {
        let snapshot = try TestData.snapshot()
        guard case .at(let resetDate) = snapshot.session.reset else {
            Issue.record("expected reset date")
            return
        }

        let window = snapshot.session.clearingUsageIfReset(at: resetDate)

        #expect(window.usedPercent == nil)
        #expect(window.reset == .at(resetDate))
        #expect(snapshot.session.clearingUsageIfReset(at: resetDate.addingTimeInterval(-1)) == snapshot.session)
    }

    private func withDefaults(_ body: (UserDefaults) throws -> Void) throws {
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        try body(defaults)
    }
}
