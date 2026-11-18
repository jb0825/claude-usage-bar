import Foundation

enum RefreshReason: String, Sendable {
    case activation
    case wake
    case poll
    case hook
    case scheduled
    case popover
    case manual

    fileprivate var requestsRerunWhileInFlight: Bool {
        switch self {
        case .manual, .popover: false
        case .activation, .wake, .poll, .hook, .scheduled: true
        }
    }
}

enum RefreshOutcome: Equatable, Sendable {
    case success
    case retryable(retryAfter: TimeInterval?)
    case nonRetryable
    case cancelled

    init(_ result: Result<UsageSnapshot, any Error>) {
        switch result {
        case .success:
            self = .success
        case .failure(is CancellationError):
            self = .cancelled
        case .failure(let error as UsageError):
            self = Self.outcome(for: error)
        case .failure:
            self = .retryable(retryAfter: nil)
        }
    }

    private static func outcome(for error: UsageError) -> RefreshOutcome {
        switch error {
        case .network:
            return .retryable(retryAfter: nil)
        case .httpStatus(let status, let retryAfter)
            where status == Constants.API.rateLimitedStatus
            || Constants.API.serverErrorStatuses.contains(status):
            return .retryable(retryAfter: retryAfter)
        case .credentials, .unauthorized, .httpStatus, .invalidResponse:
            return .nonRetryable
        }
    }
}

// 비공식 API에 부담을 주지 않도록 호출 시점 규칙을 한곳에 모은다.
// 시계와 타이머에 의존하지 않아 디바운스와 백오프를 그대로 테스트할 수 있다.
struct RefreshScheduler {
    enum Decision: Equatable {
        case startNow
        case startAt(Date)
        case ignore
    }

    private(set) var isInFlight = false
    private(set) var lastAttemptAt: Date?
    private var backoffUntil: Date?
    private var consecutiveFailures = 0
    private var needsRerun = false

    init(lastAttemptAt: Date? = nil) {
        self.lastAttemptAt = lastAttemptAt
    }

    mutating func request(_ reason: RefreshReason, now: Date) -> Decision {
        if isInFlight {
            if reason.requestsRerunWhileInFlight {
                needsRerun = true
            }
            return .ignore
        }

        guard let earliest = earliestStart(for: reason), earliest > now else {
            return .startNow
        }
        // 팝오버는 최근 값이 있으면 그대로 보여주면 되므로 나중으로 예약하지 않는다.
        return reason == .popover ? .ignore : .startAt(earliest)
    }

    mutating func didStart(at date: Date) {
        isInFlight = true
        needsRerun = false
        lastAttemptAt = date
    }

    /// 완료 후 자동으로 한 번 더 실행해야 하면 그 시각을 돌려준다.
    mutating func didFinish(_ outcome: RefreshOutcome, at date: Date) -> Date? {
        isInFlight = false
        // 키체인 허용 대기처럼 요청이 늦게 나갈 수 있어 완료 시각부터 최소 간격을 센다.
        lastAttemptAt = date
        var needsFollowUp = needsRerun
        needsRerun = false

        switch outcome {
        case .success, .nonRetryable:
            consecutiveFailures = 0
            backoffUntil = nil
        case .retryable(let retryAfter):
            consecutiveFailures += 1
            // 실제 429 응답이 Retry-After: 0을 보냈다. 그 값만 따르면 간격이 늘지 않으므로 더 긴 쪽을 쓴다.
            let backoff = Self.backoffDelay(failures: consecutiveFailures)
            backoffUntil = date.addingTimeInterval(max(retryAfter ?? 0, backoff))
            needsFollowUp = true
        case .cancelled:
            break
        }

        return needsFollowUp ? debouncedStart() : nil
    }

    mutating func cancelInFlight() {
        isInFlight = false
        needsRerun = false
    }

    static func backoffDelay(failures: Int) -> TimeInterval {
        let multiplier = pow(2, Double(max(failures - 1, 0)))
        return min(Constants.Refresh.backoffBase * multiplier, Constants.Refresh.backoffMaximum)
    }

    private func earliestStart(for reason: RefreshReason) -> Date? {
        switch reason {
        case .manual:
            return nil
        case .wake:
            return backoffUntil
        case .activation, .poll, .hook, .scheduled, .popover:
            return debouncedStart()
        }
    }

    private func debouncedStart() -> Date? {
        let debounceEnd = lastAttemptAt?.addingTimeInterval(Constants.Refresh.minimumInterval)
        return [debounceEnd, backoffUntil].compactMap { $0 }.max()
    }
}

@MainActor
protocol DelayScheduling {
    /// 반환된 객체를 해제하면 예약이 취소된다.
    func schedule(after delay: TimeInterval, action: @escaping @MainActor () -> Void) -> AnyObject
}

struct DispatchDelayScheduler: DelayScheduling {
    func schedule(after delay: TimeInterval, action: @escaping @MainActor () -> Void) -> AnyObject {
        DispatchDelay(delay: delay, action: action)
    }
}

private final class DispatchDelay {
    private let source: DispatchSourceTimer

    init(delay: TimeInterval, action: @escaping @MainActor () -> Void) {
        source = DispatchSource.makeTimerSource(queue: .main)
        source.schedule(
            deadline: .now() + delay,
            repeating: .never,
            leeway: .seconds(Int(AppCoordinator.pollLeeway(for: delay)))
        )
        source.setEventHandler {
            Task { @MainActor in
                action()
            }
        }
        source.resume()
    }

    deinit {
        source.cancel()
    }
}
