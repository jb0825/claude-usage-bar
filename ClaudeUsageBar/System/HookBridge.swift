import Dispatch
import notify
import os

@MainActor
protocol HookMonitoring: AnyObject {
    func start(onSignal: @escaping () -> Void)
}

// Claude Code hook의 notifyutil 신호를 받는다. Darwin notify는 내용 없는 신호만 전달하고
// 대기 중 CPU를 쓰지 않는다. 다른 프로세스도 보낼 수 있지만 디바운스된 조회만 일으킨다.
@MainActor
final class HookBridge: HookMonitoring {
    private static let logger = Logger(
        subsystem: Constants.Logging.subsystem,
        category: "HookBridge"
    )

    private var token: Int32?
    private var onSignal: (() -> Void)?

    func start(onSignal: @escaping () -> Void) {
        guard token == nil else { return }
        self.onSignal = onSignal

        var newToken: Int32 = 0
        let status = notify_register_dispatch(
            Constants.Hook.notificationName,
            &newToken,
            .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.onSignal?()
            }
        }

        guard status == UInt32(NOTIFY_STATUS_OK) else {
            Self.logger.info("hook registration failed: \(status, privacy: .public)")
            return
        }
        token = newToken
    }

    func stop() {
        guard let token else { return }
        notify_cancel(token)
        self.token = nil
        onSignal = nil
    }
}
