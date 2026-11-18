import Observation

enum RefreshFailure: Equatable, Sendable {
    case authentication
    case temporary

    init(error: UsageError) {
        switch error {
        case .credentials, .unauthorized:
            self = .authentication
        case .httpStatus, .network, .invalidResponse:
            self = .temporary
        }
    }
}

@MainActor
@Observable
final class UsageStore {
    private(set) var snapshot: UsageSnapshot?
    private(set) var failure: RefreshFailure?
    private(set) var isRefreshing = false
    private(set) var isActive = false

    func setActive(_ isActive: Bool) {
        self.isActive = isActive
    }

    func restore(_ snapshot: UsageSnapshot) {
        self.snapshot = snapshot
    }

    func beginRefresh() {
        isRefreshing = true
    }

    func finishRefresh(with snapshot: UsageSnapshot) {
        self.snapshot = snapshot
        failure = nil
        isRefreshing = false
    }

    // 실패해도 마지막 값은 유지해 메뉴바가 비지 않게 한다.
    func finishRefresh(with failure: RefreshFailure) {
        self.failure = failure
        isRefreshing = false
    }

    func cancelRefresh() {
        isRefreshing = false
    }
}
