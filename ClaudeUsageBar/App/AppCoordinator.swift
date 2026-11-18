import Foundation
import os

@MainActor
final class AppCoordinator {
    enum State: String {
        case idle
        case active
    }

    private static let logger = Logger(
        subsystem: Constants.Logging.subsystem,
        category: "AppCoordinator"
    )

    private let service: any UsageFetching
    private let store: UsageStore
    private let appMonitor: any ClaudeAppMonitoring
    private let powerMonitor: any PowerMonitoring
    private let hookMonitor: any HookMonitoring
    private let delayScheduler: any DelayScheduling
    private let cache: any UsageStateCaching
    private let now: @MainActor () -> Date

    private(set) var pollInterval: TimeInterval
    private(set) var state = State.idle
    private(set) var refreshTask: Task<Void, Never>?
    private var scheduler = RefreshScheduler()
    private var pollTimer: PollTimer?
    private var pendingRefresh: AnyObject?
    private var pendingRefreshDate: Date?
    private var isAsleep = false
    private var isStarted = false
    private var refreshGeneration = 0

    init(
        service: any UsageFetching,
        store: UsageStore,
        appMonitor: any ClaudeAppMonitoring,
        powerMonitor: any PowerMonitoring,
        hookMonitor: any HookMonitoring,
        delayScheduler: any DelayScheduling = DispatchDelayScheduler(),
        cache: any UsageStateCaching = UserDefaultsUsageCache(),
        now: @escaping @MainActor () -> Date = { Date() },
        pollInterval: TimeInterval = Constants.Polling.defaultInterval
    ) {
        self.service = service
        self.store = store
        self.appMonitor = appMonitor
        self.powerMonitor = powerMonitor
        self.hookMonitor = hookMonitor
        self.delayScheduler = delayScheduler
        self.cache = cache
        self.now = now
        self.pollInterval = pollInterval
    }

    var isPollTimerRunning: Bool {
        pollTimer?.isRunning == true
    }

    func updatePollInterval(_ interval: TimeInterval) {
        guard interval != pollInterval else { return }
        pollInterval = interval
        guard state == .active else { return }

        let timer = makePollTimer()
        pollTimer = timer
        if !isAsleep {
            timer.resume()
        }
    }

    func start() {
        guard !isStarted else { return }
        isStarted = true
        restorePersistedState()

        appMonitor.start { [weak self] isRunning in
            self?.claudeRunningStateChanged(isRunning)
        }
        powerMonitor.start(
            onSleep: { [weak self] in self?.systemWillSleep() },
            onWake: { [weak self] in self?.systemDidWake() }
        )
        hookMonitor.start { [weak self] in
            self?.requestRefresh(reason: .hook)
        }
        claudeRunningStateChanged(appMonitor.isClaudeRunning)
    }

    @discardableResult
    func requestRefresh(reason: RefreshReason) -> Task<Void, Never>? {
        guard state == .active, !isAsleep else { return nil }

        Self.logger.debug("refresh requested: \(reason.rawValue, privacy: .public)")
        switch scheduler.request(reason, now: now()) {
        case .startNow:
            return startRefresh(reason: reason)
        case .startAt(let date):
            schedulePendingRefresh(at: date)
            return nil
        case .ignore:
            return nil
        }
    }

    nonisolated static func pollLeeway(for interval: TimeInterval) -> TimeInterval {
        max(interval * Constants.Polling.leewayRatio, Constants.Polling.minimumLeeway)
    }

    // 재시작해도 마지막 값을 바로 보여주고, 방금 조회했다면 API를 다시 호출하지 않는다.
    private func restorePersistedState() {
        guard let state = cache.load() else { return }
        let date = now()

        if let snapshot = state.snapshot {
            store.restore(snapshot.clearingExpiredUsage(at: date))
        }
        // 시스템 시계가 뒤로 바뀌면 미래 시각이 남아 조회가 오래 막힐 수 있다.
        if let lastAttemptAt = state.lastAttemptAt, lastAttemptAt <= date {
            scheduler = RefreshScheduler(lastAttemptAt: lastAttemptAt)
        }
    }

    private func persistState() {
        cache.save(PersistedUsageState(
            snapshot: store.snapshot,
            lastAttemptAt: scheduler.lastAttemptAt
        ))
    }

    private func claudeRunningStateChanged(_ isRunning: Bool) {
        if isRunning {
            activate()
        } else {
            deactivate()
        }
    }

    private func activate() {
        guard state == .idle else { return }
        transition(to: .active)
        store.setActive(true)

        let timer = makePollTimer()
        pollTimer = timer
        if isAsleep {
            timer.suspend()
        } else {
            timer.resume()
            requestRefresh(reason: .activation)
        }
    }

    private func deactivate() {
        guard state == .active else { return }
        transition(to: .idle)
        store.setActive(false)
        pollTimer = nil
        cancelCurrentRefresh()
    }

    private func systemWillSleep() {
        isAsleep = true
        guard state == .active else { return }
        pollTimer?.suspend()
        cancelCurrentRefresh()
    }

    private func systemDidWake() {
        isAsleep = false
        guard state == .active else { return }
        pollTimer?.resume()
        requestRefresh(reason: .wake)
    }

    private func transition(to newState: State) {
        state = newState
        Self.logger.debug("state changed: \(newState.rawValue, privacy: .public)")
    }

    private func startRefresh(reason: RefreshReason) -> Task<Void, Never> {
        Self.logger.debug("refresh started: \(reason.rawValue, privacy: .public)")
        cancelPendingRefresh()
        scheduler.didStart(at: now())
        persistState()
        refreshGeneration += 1
        let generation = refreshGeneration
        store.beginRefresh()

        let task = Task<Void, Never> { [weak self] in
            await self?.performRefresh(generation: generation)
        }
        refreshTask = task
        return task
    }

    private func cancelCurrentRefresh() {
        refreshGeneration += 1
        refreshTask?.cancel()
        refreshTask = nil
        scheduler.cancelInFlight()
        cancelPendingRefresh()
        store.cancelRefresh()
    }

    // 예약은 하나만 유지해 여러 트리거가 호출 1회로 합쳐지게 한다.
    private func schedulePendingRefresh(at date: Date) {
        if pendingRefresh != nil, let pendingRefreshDate, pendingRefreshDate <= date {
            return
        }

        pendingRefreshDate = date
        pendingRefresh = delayScheduler.schedule(
            after: max(date.timeIntervalSince(now()), 0)
        ) { [weak self] in
            self?.cancelPendingRefresh()
            self?.requestRefresh(reason: .scheduled)
        }
    }

    private func cancelPendingRefresh() {
        pendingRefresh = nil
        pendingRefreshDate = nil
    }

    private func makePollTimer() -> PollTimer {
        PollTimer(
            interval: pollInterval,
            leeway: Self.pollLeeway(for: pollInterval)
        ) { [weak self] in
            Task { @MainActor in
                self?.requestRefresh(reason: .poll)
            }
        }
    }

    private func performRefresh(generation: Int) async {
        let result: Result<UsageSnapshot, any Error>
        do {
            result = .success(try await service.fetchUsage())
        } catch {
            result = .failure(error)
        }

        // idle 전환이나 sleep 뒤에 도착한 응답은 현재 상태에 반영하지 않는다.
        guard generation == refreshGeneration else { return }
        refreshTask = nil
        apply(result)

        let followUp = scheduler.didFinish(RefreshOutcome(result), at: now())
        persistState()
        if let followUp {
            schedulePendingRefresh(at: followUp)
        }
    }

    private func apply(_ result: Result<UsageSnapshot, any Error>) {
        switch result {
        case .success(let snapshot):
            store.finishRefresh(with: snapshot)
            Self.logger.debug(
                """
                refresh succeeded: session=\(snapshot.session.usedPercent ?? -1, privacy: .public) \
                weekly=\(snapshot.weekly.usedPercent ?? -1, privacy: .public)
                """
            )
        case .failure(is CancellationError):
            store.cancelRefresh()
        case .failure(let error as UsageError):
            Self.logger.info("refresh failed: \(String(describing: error), privacy: .public)")
            store.finishRefresh(with: RefreshFailure(error: error))
        case .failure:
            Self.logger.info("refresh failed: unexpected error")
            store.finishRefresh(with: .temporary)
        }
    }
}
