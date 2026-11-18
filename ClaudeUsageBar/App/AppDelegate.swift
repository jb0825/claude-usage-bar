import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var coordinator: AppCoordinator?
    private var statusItemController: StatusItemController?
    private var statusMenuController: StatusMenuController?
    private var hookBridge: HookBridge?

    func applicationDidFinishLaunching(_ notification: Notification) {
        guard Self.shouldStartServices(environment: ProcessInfo.processInfo.environment) else {
            return
        }

        let store = UsageStore()
        let service = UsageService(credentials: CredentialStore())
        let hookBridge = HookBridge()
        let pollingSettings = PollingSettings()
        let coordinator = AppCoordinator(
            service: service,
            store: store,
            appMonitor: ClaudeAppWatcher(),
            powerMonitor: PowerObserver(),
            hookMonitor: hookBridge,
            pollInterval: pollingSettings.interval
        )
        let refresh = { [weak coordinator] in
            coordinator?.requestRefresh(reason: .manual)
            return
        }
        let statusMenuController = StatusMenuController(
            loginItem: LoginItemController(),
            pollingSettings: pollingSettings,
            onRefresh: refresh,
            onPollIntervalChange: { [weak coordinator] interval in
                coordinator?.updatePollInterval(interval)
            }
        )

        statusItemController = StatusItemController(
            store: store,
            contextMenu: statusMenuController.menu,
            onRefresh: refresh,
            onPopoverOpen: { [weak coordinator] in
                coordinator?.requestRefresh(reason: .popover)
            }
        )
        self.statusMenuController = statusMenuController
        self.hookBridge = hookBridge
        self.coordinator = coordinator
        coordinator.start()
    }

    func applicationWillTerminate(_ notification: Notification) {
        hookBridge?.stop()
    }

    // 단위 테스트는 이 앱을 호스트로 실행한다. 테스트 중 키체인과 네트워크에 접근하면 안 된다.
    nonisolated static func shouldStartServices(environment: [String: String]) -> Bool {
        environment[Constants.Environment.xcTestConfiguration] == nil
    }
}
