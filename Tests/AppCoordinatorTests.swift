import Foundation
import Testing
@testable import ClaudeUsageBar

@MainActor
struct AppCoordinatorTests {
    @MainActor
    private struct Harness {
        let service: FakeUsageService
        let store = UsageStore()
        let appMonitor: FakeClaudeMonitor
        let powerMonitor = FakePowerMonitor()
        let hookMonitor = FakeHookMonitor()
        let delays = FakeDelayScheduler()
        let clock = FakeClock()
        let cache: FakeUsageCache
        let coordinator: AppCoordinator

        init(
            results: [Result<UsageSnapshot, UsageError>],
            isClaudeRunning: Bool = true,
            waitsForRelease: Bool = false,
            cached: PersistedUsageState? = nil
        ) {
            service = FakeUsageService(results: results, waitsForRelease: waitsForRelease)
            cache = FakeUsageCache(initial: cached)
            appMonitor = FakeClaudeMonitor(isClaudeRunning: isClaudeRunning)
            let clock = clock
            coordinator = AppCoordinator(
                service: service,
                store: store,
                appMonitor: appMonitor,
                powerMonitor: powerMonitor,
                hookMonitor: hookMonitor,
                delayScheduler: delays,
                cache: cache,
                now: { clock.now }
            )
        }

        func startAndWait() async {
            coordinator.start()
            await coordinator.refreshTask?.value
        }
    }

    @Test func startsIdleWhenClaudeIsNotRunning() async {
        let harness = Harness(results: [], isClaudeRunning: false)

        await harness.startAndWait()

        #expect(harness.coordinator.state == .idle)
        #expect(!harness.store.isActive)
        #expect(!harness.coordinator.isPollTimerRunning)
        #expect(await harness.service.fetchCount == 0)
    }

    @Test func startsActiveAndRefreshesWhenClaudeIsRunning() async throws {
        let snapshot = try TestData.snapshot()
        let harness = Harness(results: [.success(snapshot)])

        await harness.startAndWait()

        #expect(harness.coordinator.state == .active)
        #expect(harness.store.isActive)
        #expect(harness.store.snapshot == snapshot)
        #expect(harness.store.failure == nil)
        #expect(!harness.store.isRefreshing)
        #expect(harness.coordinator.isPollTimerRunning)
    }

    @Test func claudeLaunchActivates() async throws {
        let harness = Harness(results: [.success(try TestData.snapshot())], isClaudeRunning: false)
        await harness.startAndWait()

        harness.appMonitor.send(isRunning: true)
        await harness.coordinator.refreshTask?.value

        #expect(harness.coordinator.state == .active)
        #expect(await harness.service.fetchCount == 1)
    }

    @Test func claudeTerminationGoesIdleAndIgnoresRequests() async throws {
        let harness = Harness(results: [.success(try TestData.snapshot())])
        await harness.startAndWait()

        harness.appMonitor.send(isRunning: false)
        let task = harness.coordinator.requestRefresh(reason: .manual)

        #expect(task == nil)
        #expect(harness.coordinator.state == .idle)
        #expect(!harness.store.isActive)
        #expect(!harness.coordinator.isPollTimerRunning)
        #expect(await harness.service.fetchCount == 1)
    }

    @Test func responseArrivingAfterTerminationIsIgnored() async throws {
        let harness = Harness(
            results: [.success(try TestData.snapshot())],
            waitsForRelease: true
        )
        harness.coordinator.start()
        let task = harness.coordinator.refreshTask

        harness.appMonitor.send(isRunning: false)
        await harness.service.release()
        await task?.value

        #expect(harness.store.snapshot == nil)
        #expect(!harness.store.isRefreshing)
    }

    @Test func sleepSuspendsAndWakeRefreshes() async throws {
        let snapshot = try TestData.snapshot()
        let harness = Harness(results: [.success(snapshot), .success(snapshot)])
        await harness.startAndWait()

        harness.powerMonitor.sleep()
        #expect(!harness.coordinator.isPollTimerRunning)
        #expect(harness.coordinator.requestRefresh(reason: .manual) == nil)

        harness.powerMonitor.wake()
        await harness.coordinator.refreshTask?.value

        #expect(harness.coordinator.isPollTimerRunning)
        #expect(await harness.service.fetchCount == 2)
    }

    @Test func wakeWhileIdleDoesNothing() async {
        let harness = Harness(results: [], isClaudeRunning: false)
        await harness.startAndWait()

        harness.powerMonitor.sleep()
        harness.powerMonitor.wake()

        #expect(harness.coordinator.refreshTask == nil)
        #expect(await harness.service.fetchCount == 0)
    }

    @Test func claudeLaunchDuringSleepWaitsForWake() async throws {
        let harness = Harness(results: [.success(try TestData.snapshot())], isClaudeRunning: false)
        await harness.startAndWait()

        harness.powerMonitor.sleep()
        harness.appMonitor.send(isRunning: true)
        #expect(harness.coordinator.state == .active)
        #expect(!harness.coordinator.isPollTimerRunning)
        #expect(await harness.service.fetchCount == 0)

        harness.powerMonitor.wake()
        await harness.coordinator.refreshTask?.value

        #expect(harness.coordinator.isPollTimerRunning)
        #expect(await harness.service.fetchCount == 1)
    }

    @Test func failureKeepsLastSnapshot() async throws {
        let snapshot = try TestData.snapshot()
        let harness = Harness(results: [.success(snapshot), .failure(.network)])
        await harness.startAndWait()

        await harness.coordinator.requestRefresh(reason: .manual)?.value

        #expect(harness.store.snapshot == snapshot)
        #expect(harness.store.failure == .temporary)
    }

    @Test func changingPollIntervalKeepsTimerRunning() async throws {
        let harness = Harness(results: [.success(try TestData.snapshot())])
        await harness.startAndWait()

        harness.coordinator.updatePollInterval(600)

        #expect(harness.coordinator.pollInterval == 600)
        #expect(harness.coordinator.isPollTimerRunning)
    }

    @Test func changingPollIntervalWhileAsleepWaitsForWake() async throws {
        let snapshot = try TestData.snapshot()
        let harness = Harness(results: [.success(snapshot), .success(snapshot)])
        await harness.startAndWait()
        harness.powerMonitor.sleep()

        harness.coordinator.updatePollInterval(600)
        #expect(!harness.coordinator.isPollTimerRunning)

        harness.powerMonitor.wake()
        await harness.coordinator.refreshTask?.value
        #expect(harness.coordinator.isPollTimerRunning)
    }

    @Test func restartWithinMinimumIntervalShowsCacheWithoutCalling() async throws {
        let snapshot = try TestData.snapshot()
        let lastAttempt = FakeClock().now.addingTimeInterval(-20)
        let harness = Harness(
            results: [.success(snapshot)],
            cached: PersistedUsageState(snapshot: snapshot, lastAttemptAt: lastAttempt)
        )

        await harness.startAndWait()

        #expect(harness.store.snapshot == snapshot)
        #expect(harness.delays.activeDelays == [40])
        #expect(await harness.service.fetchCount == 0)

        harness.clock.advance(by: 40)
        harness.delays.fireActive()
        await harness.coordinator.refreshTask?.value

        #expect(await harness.service.fetchCount == 1)
    }

    @Test func restartAfterMinimumIntervalRefreshesImmediately() async throws {
        let snapshot = try TestData.snapshot()
        let lastAttempt = FakeClock().now.addingTimeInterval(-60)
        let harness = Harness(
            results: [.success(snapshot)],
            cached: PersistedUsageState(snapshot: nil, lastAttemptAt: lastAttempt)
        )

        await harness.startAndWait()

        #expect(harness.delays.activeDelays.isEmpty)
        #expect(await harness.service.fetchCount == 1)
    }

    @Test func futureAttemptTimeIsIgnored() async throws {
        let future = FakeClock().now.addingTimeInterval(3_600)
        let harness = Harness(
            results: [.success(try TestData.snapshot())],
            cached: PersistedUsageState(snapshot: nil, lastAttemptAt: future)
        )

        await harness.startAndWait()

        #expect(harness.delays.activeDelays.isEmpty)
        #expect(await harness.service.fetchCount == 1)
    }

    @Test func expiredCachedUsageIsNotRestored() async throws {
        let snapshot = try TestData.snapshot()
        let harness = Harness(
            results: [],
            isClaudeRunning: false,
            cached: PersistedUsageState(snapshot: snapshot, lastAttemptAt: nil)
        )
        // TestData의 초기화 시각은 FakeClock보다 훨씬 뒤라 시계를 그 이후로 옮긴다.
        harness.clock.advance(by: 2_000_000_000)

        await harness.startAndWait()

        #expect(harness.store.snapshot?.session.usedPercent == nil)
        #expect(harness.store.snapshot?.weekly.usedPercent == nil)
        #expect(harness.store.snapshot?.fetchedAt == snapshot.fetchedAt)
    }

    @Test func refreshPersistsAttemptAndResult() async throws {
        let snapshot = try TestData.snapshot()
        let harness = Harness(results: [.success(snapshot)])

        await harness.startAndWait()

        #expect(harness.cache.saved.first?.snapshot == nil)
        #expect(harness.cache.saved.first?.lastAttemptAt == harness.clock.now)
        #expect(harness.cache.saved.last?.snapshot == snapshot)
    }

    @Test func repeatedHooksMergeIntoOneTrailingRefresh() async throws {
        let snapshot = try TestData.snapshot()
        let harness = Harness(results: [.success(snapshot), .success(snapshot)])
        await harness.startAndWait()

        harness.clock.advance(by: 10)
        harness.hookMonitor.send()
        harness.clock.advance(by: 10)
        harness.hookMonitor.send()

        #expect(harness.delays.activeDelays == [50])
        #expect(await harness.service.fetchCount == 1)

        harness.clock.advance(by: 40)
        harness.delays.fireActive()
        await harness.coordinator.refreshTask?.value

        #expect(harness.delays.activeDelays.isEmpty)
        #expect(await harness.service.fetchCount == 2)
    }

    @Test func hookIsIgnoredWhileIdle() async {
        let harness = Harness(results: [], isClaudeRunning: false)
        await harness.startAndWait()

        harness.hookMonitor.send()

        #expect(harness.delays.activeDelays.isEmpty)
        #expect(await harness.service.fetchCount == 0)
    }

    @Test func hookDuringRefreshRunsOnceMoreAfterCompletion() async throws {
        let harness = Harness(
            results: [.success(try TestData.snapshot())],
            waitsForRelease: true
        )
        harness.coordinator.start()
        let task = harness.coordinator.refreshTask

        harness.hookMonitor.send()
        await harness.service.release()
        await task?.value

        #expect(harness.delays.activeDelays == [60])
    }

    @Test func retryableFailureSchedulesBackoffRetry() async throws {
        let harness = Harness(results: [.failure(.network), .success(try TestData.snapshot())])
        await harness.startAndWait()

        #expect(harness.delays.activeDelays == [60])

        harness.clock.advance(by: 60)
        harness.delays.fireActive()
        await harness.coordinator.refreshTask?.value

        #expect(harness.store.failure == nil)
        #expect(await harness.service.fetchCount == 2)
    }

    @Test func authenticationFailureWaitsForNextTrigger() async {
        let harness = Harness(results: [.failure(.unauthorized)])

        await harness.startAndWait()

        #expect(harness.delays.activeDelays.isEmpty)
    }

    @Test func manualRefreshReplacesPendingRefresh() async throws {
        let snapshot = try TestData.snapshot()
        let harness = Harness(results: [.success(snapshot), .success(snapshot)])
        await harness.startAndWait()
        harness.hookMonitor.send()

        await harness.coordinator.requestRefresh(reason: .manual)?.value

        #expect(harness.delays.activeDelays.isEmpty)
        #expect(await harness.service.fetchCount == 2)
    }

    @Test func terminationCancelsPendingRefresh() async throws {
        let harness = Harness(results: [.success(try TestData.snapshot())])
        await harness.startAndWait()
        harness.hookMonitor.send()

        harness.appMonitor.send(isRunning: false)

        #expect(harness.delays.activeDelays.isEmpty)
    }

    @Test func sleepCancelsPendingRefresh() async throws {
        let harness = Harness(results: [.success(try TestData.snapshot())])
        await harness.startAndWait()
        harness.hookMonitor.send()

        harness.powerMonitor.sleep()

        #expect(harness.delays.activeDelays.isEmpty)
    }

    @Test func authenticationErrorIsReportedSeparately() async {
        let harness = Harness(results: [.failure(.unauthorized)])

        await harness.startAndWait()

        #expect(harness.store.failure == .authentication)
    }

    @Test func refreshInProgressIgnoresNewRequest() async throws {
        let harness = Harness(
            results: [.success(try TestData.snapshot())],
            waitsForRelease: true
        )
        harness.coordinator.start()
        let first = harness.coordinator.refreshTask

        let second = harness.coordinator.requestRefresh(reason: .manual)
        await harness.service.release()
        await first?.value

        #expect(first != nil)
        #expect(second == nil)
        #expect(await harness.service.fetchCount == 1)
    }

    @Test(arguments: [(60.0, 30.0), (300.0, 30.0), (900.0, 90.0)])
    func pollLeewayUsesTenPercentWithMinimum(interval: Double, expected: Double) {
        #expect(AppCoordinator.pollLeeway(for: interval) == expected)
    }
}
