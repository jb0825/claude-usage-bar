import Foundation

// 사용량 숫자와 시각만 저장한다. 인증 토큰은 이 구조에 넣지 않는다.
struct PersistedUsageState: Codable, Equatable, Sendable {
    let snapshot: UsageSnapshot?
    let lastAttemptAt: Date?
}

@MainActor
protocol UsageStateCaching {
    func load() -> PersistedUsageState?
    func save(_ state: PersistedUsageState)
}

struct UserDefaultsUsageCache: UsageStateCaching {
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func load() -> PersistedUsageState? {
        guard let data = defaults.data(forKey: Constants.Cache.usageStateKey) else {
            return nil
        }
        return try? JSONDecoder().decode(PersistedUsageState.self, from: data)
    }

    func save(_ state: PersistedUsageState) {
        guard let data = try? JSONEncoder().encode(state) else { return }
        defaults.set(data, forKey: Constants.Cache.usageStateKey)
    }
}
