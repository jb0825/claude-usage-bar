import Foundation

final class PollTimer {
    private let source: DispatchSourceTimer
    private let interval: TimeInterval
    private let leeway: TimeInterval
    private(set) var isRunning = false

    init(interval: TimeInterval, leeway: TimeInterval, onFire: @escaping @Sendable () -> Void) {
        self.interval = interval
        self.leeway = leeway
        source = DispatchSource.makeTimerSource(queue: .main)
        source.setEventHandler(handler: onFire)
    }

    func resume() {
        guard !isRunning else { return }
        // sleep 중 지난 호출이 몰려 60초 안에 재호출되지 않도록 다음 시각을 새로 잡는다.
        source.schedule(
            deadline: .now() + interval,
            repeating: interval,
            leeway: .seconds(Int(leeway))
        )
        source.resume()
        isRunning = true
    }

    func suspend() {
        guard isRunning else { return }
        source.suspend()
        isRunning = false
    }

    deinit {
        // 일시정지 상태의 DispatchSource를 해제하면 크래시하므로 먼저 재개한다.
        if !isRunning {
            source.resume()
        }
        source.cancel()
    }
}
