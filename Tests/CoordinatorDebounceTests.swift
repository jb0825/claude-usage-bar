import Foundation
import Testing
@testable import ClaudeUsageBar

struct CoordinatorDebounceTests {
    private let start = Date(timeIntervalSince1970: 1_000_000)

    private func date(_ offset: TimeInterval) -> Date {
        start.addingTimeInterval(offset)
    }

    private func schedulerAfterSuccess() -> RefreshScheduler {
        var scheduler = RefreshScheduler()
        scheduler.didStart(at: start)
        _ = scheduler.didFinish(.success, at: start)
        return scheduler
    }

    @Test func firstAutomaticTriggerStartsImmediately() {
        var scheduler = RefreshScheduler()

        #expect(scheduler.request(.hook, now: start) == .startNow)
    }

    @Test(arguments: [RefreshReason.activation, .hook, .poll, .scheduled])
    func automaticTriggerInsideWindowIsTrailing(reason: RefreshReason) {
        var scheduler = schedulerAfterSuccess()

        #expect(scheduler.request(reason, now: date(59)) == .startAt(date(60)))
        #expect(scheduler.request(reason, now: date(60)) == .startNow)
    }

    @Test(arguments: [RefreshReason.manual, .wake])
    func immediateTriggersSkipDebounce(reason: RefreshReason) {
        var scheduler = schedulerAfterSuccess()

        #expect(scheduler.request(reason, now: date(1)) == .startNow)
    }

    @Test func failedAttemptAlsoStartsDebounceWindow() {
        var scheduler = RefreshScheduler()
        scheduler.didStart(at: start)
        _ = scheduler.didFinish(.nonRetryable, at: start)

        #expect(scheduler.request(.hook, now: date(10)) == .startAt(date(60)))
    }

    @Test func manualDuringRefreshIsIgnoredWithoutRerun() {
        var scheduler = RefreshScheduler()
        scheduler.didStart(at: start)

        #expect(scheduler.request(.manual, now: date(1)) == .ignore)
        #expect(scheduler.didFinish(.success, at: date(2)) == nil)
    }

    @Test func automaticDuringRefreshRunsOnceMore() {
        var scheduler = RefreshScheduler()
        scheduler.didStart(at: start)

        #expect(scheduler.request(.hook, now: date(1)) == .ignore)
        #expect(scheduler.request(.poll, now: date(2)) == .ignore)
        #expect(scheduler.didFinish(.success, at: date(3)) == date(63))
    }

    @Test func debounceCountsFromCompletionOfSlowRefresh() {
        var scheduler = RefreshScheduler()
        scheduler.didStart(at: start)
        _ = scheduler.didFinish(.success, at: date(59))

        #expect(scheduler.request(.hook, now: date(62)) == .startAt(date(119)))
    }

    @Test func manualDuringRefreshKeepsRequestedRerun() {
        var scheduler = RefreshScheduler()
        scheduler.didStart(at: start)

        _ = scheduler.request(.hook, now: date(1))
        _ = scheduler.request(.manual, now: date(2))

        #expect(scheduler.didFinish(.success, at: date(3)) == date(63))
    }

    @Test func popoverRefreshesOnlyWhenValueIsOld() {
        var scheduler = schedulerAfterSuccess()

        #expect(scheduler.request(.popover, now: date(59)) == .ignore)
        #expect(scheduler.request(.popover, now: date(60)) == .startNow)
    }

    @Test func popoverDuringRefreshDoesNotRequestRerun() {
        var scheduler = RefreshScheduler()
        scheduler.didStart(at: start)

        #expect(scheduler.request(.popover, now: date(1)) == .ignore)
        #expect(scheduler.didFinish(.success, at: date(2)) == nil)
    }

    @Test func backoffDoublesUpToMaximum() {
        let delays = (1...6).map(RefreshScheduler.backoffDelay(failures:))

        #expect(delays == [60, 120, 240, 480, 900, 900])
    }

    @Test func repeatedFailuresExtendRetryTime() {
        var scheduler = RefreshScheduler()

        scheduler.didStart(at: start)
        #expect(scheduler.didFinish(.retryable(retryAfter: nil), at: start) == date(60))

        scheduler.didStart(at: date(60))
        #expect(scheduler.didFinish(.retryable(retryAfter: nil), at: date(60)) == date(180))
    }

    @Test func longerRetryAfterOverridesBackoff() {
        var scheduler = RefreshScheduler()
        scheduler.didStart(at: start)

        #expect(scheduler.didFinish(.retryable(retryAfter: 300), at: start) == date(300))
    }

    @Test func zeroRetryAfterStillBacksOff() {
        var scheduler = RefreshScheduler()

        scheduler.didStart(at: start)
        #expect(scheduler.didFinish(.retryable(retryAfter: 0), at: start) == date(60))

        scheduler.didStart(at: date(60))
        #expect(scheduler.didFinish(.retryable(retryAfter: 0), at: date(60)) == date(180))

        scheduler.didStart(at: date(180))
        #expect(scheduler.didFinish(.retryable(retryAfter: 0), at: date(180)) == date(420))
    }

    @Test func shortRetryAfterKeepsMinimumInterval() {
        var scheduler = RefreshScheduler()
        scheduler.didStart(at: start)

        #expect(scheduler.didFinish(.retryable(retryAfter: 5), at: start) == date(60))
    }

    @Test(arguments: [RefreshReason.activation, .wake, .poll, .hook])
    func automaticTriggersRespectBackoff(reason: RefreshReason) {
        var scheduler = RefreshScheduler()
        scheduler.didStart(at: start)
        _ = scheduler.didFinish(.retryable(retryAfter: 300), at: start)

        #expect(scheduler.request(reason, now: date(100)) == .startAt(date(300)))
    }

    @Test func manualBypassesBackoff() {
        var scheduler = RefreshScheduler()
        scheduler.didStart(at: start)
        _ = scheduler.didFinish(.retryable(retryAfter: 300), at: start)

        #expect(scheduler.request(.manual, now: date(100)) == .startNow)
    }

    @Test func successResetsBackoff() {
        var scheduler = RefreshScheduler()
        scheduler.didStart(at: start)
        _ = scheduler.didFinish(.retryable(retryAfter: nil), at: start)
        scheduler.didStart(at: date(60))
        _ = scheduler.didFinish(.success, at: date(60))

        scheduler.didStart(at: date(120))
        #expect(scheduler.didFinish(.retryable(retryAfter: nil), at: date(120)) == date(180))
    }

    @Test func cancelledRefreshClearsRerun() {
        var scheduler = RefreshScheduler()
        scheduler.didStart(at: start)
        _ = scheduler.request(.hook, now: date(1))

        scheduler.cancelInFlight()

        #expect(!scheduler.isInFlight)
        #expect(scheduler.didFinish(.cancelled, at: date(2)) == nil)
    }

    @Test(arguments: [
        (UsageError.network, RefreshOutcome.retryable(retryAfter: nil)),
        (.httpStatus(429, retryAfter: 30), .retryable(retryAfter: 30)),
        (.httpStatus(500), .retryable(retryAfter: nil)),
        (.httpStatus(599), .retryable(retryAfter: nil)),
        (.httpStatus(403), .nonRetryable),
        (.unauthorized, .nonRetryable),
        (.credentials(.expired), .nonRetryable),
        (.invalidResponse, .nonRetryable),
    ])
    func mapsErrorsToOutcome(error: UsageError, expected: RefreshOutcome) {
        #expect(RefreshOutcome(.failure(error)) == expected)
    }

    @Test func cancellationMapsToCancelled() {
        #expect(RefreshOutcome(.failure(CancellationError())) == .cancelled)
    }
}
