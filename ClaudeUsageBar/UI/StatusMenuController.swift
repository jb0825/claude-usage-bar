import AppKit

@MainActor
final class StatusMenuController: NSObject, NSMenuDelegate {
    let menu = NSMenu()

    private let loginItem: any LoginItemControlling
    private let pollingSettings: PollingSettings
    private let onRefresh: () -> Void
    private let onPollIntervalChange: (TimeInterval) -> Void
    private let onLoginItemError: @MainActor () -> Void
    private let loginMenuItem = NSMenuItem()
    private let intervalMenu = NSMenu()

    init(
        loginItem: any LoginItemControlling,
        pollingSettings: PollingSettings,
        onRefresh: @escaping () -> Void,
        onPollIntervalChange: @escaping (TimeInterval) -> Void,
        onLoginItemError: @escaping @MainActor () -> Void = StatusMenuController.showLoginItemError
    ) {
        self.loginItem = loginItem
        self.pollingSettings = pollingSettings
        self.onRefresh = onRefresh
        self.onPollIntervalChange = onPollIntervalChange
        self.onLoginItemError = onLoginItemError
        super.init()
        buildMenu()
        updateStates()
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        updateStates()
    }

    func selectPollInterval(_ interval: TimeInterval) {
        pollingSettings.interval = interval
        onPollIntervalChange(interval)
        updateStates()
    }

    func toggleLoginItem() {
        do {
            switch loginItem.state {
            case .enabled:
                try loginItem.setEnabled(false)
            case .requiresApproval:
                loginItem.openSystemSettings()
            case .disabled:
                try loginItem.setEnabled(true)
                // 사용자가 시스템 설정에서 허용해야 실제로 켜지는 경우가 있다.
                if loginItem.state == .requiresApproval {
                    loginItem.openSystemSettings()
                }
            }
        } catch {
            onLoginItemError()
        }
        updateStates()
    }

    private func buildMenu() {
        menu.delegate = self

        let refreshItem = NSMenuItem(
            title: String(localized: "새로고침"),
            action: #selector(refreshSelected),
            keyEquivalent: ""
        )
        refreshItem.target = self

        loginMenuItem.title = String(localized: "로그인 시 실행")
        loginMenuItem.action = #selector(loginItemSelected)
        loginMenuItem.target = self

        let intervalItem = NSMenuItem(title: String(localized: "갱신 간격"), action: nil, keyEquivalent: "")
        intervalItem.submenu = intervalMenu
        Constants.Polling.intervalOptions.forEach { intervalMenu.addItem(makeIntervalItem($0)) }

        let quitItem = NSMenuItem(
            title: String(localized: "종료"),
            action: #selector(NSApplication.terminate(_:)),
            keyEquivalent: ""
        )

        menu.addItem(refreshItem)
        menu.addItem(.separator())
        menu.addItem(loginMenuItem)
        menu.addItem(intervalItem)
        menu.addItem(.separator())
        menu.addItem(quitItem)
    }

    private func makeIntervalItem(_ interval: TimeInterval) -> NSMenuItem {
        let minutes = Int(interval / Constants.Time.secondsPerMinute)
        let item = NSMenuItem(
            title: String(localized: "\(minutes)분"),
            action: #selector(intervalSelected),
            keyEquivalent: ""
        )
        item.target = self
        item.tag = Int(interval)
        return item
    }

    private func updateStates() {
        switch loginItem.state {
        case .enabled:
            loginMenuItem.state = .on
        case .requiresApproval:
            loginMenuItem.state = .mixed
        case .disabled:
            loginMenuItem.state = .off
        }

        let selected = Int(pollingSettings.interval)
        intervalMenu.items.forEach { $0.state = $0.tag == selected ? .on : .off }
    }

    @objc private func refreshSelected() {
        onRefresh()
    }

    @objc private func loginItemSelected() {
        toggleLoginItem()
    }

    @objc private func intervalSelected(_ sender: NSMenuItem) {
        selectPollInterval(TimeInterval(sender.tag))
    }

    private static func showLoginItemError() {
        let alert = NSAlert()
        alert.messageText = String(localized: "로그인 시 실행을 변경할 수 없어요.")
        alert.informativeText = String(localized: "앱을 응용 프로그램 폴더로 옮긴 뒤 다시 시도해 주세요.")
        alert.runModal()
    }
}
