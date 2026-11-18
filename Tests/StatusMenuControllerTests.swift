import AppKit
import Testing
@testable import ClaudeUsageBar

@MainActor
private final class FakeLoginItem: LoginItemControlling {
    var state: LoginItemState
    var stateAfterEnable: LoginItemState = .enabled
    var error: (any Error)?
    private(set) var settingsOpenCount = 0

    init(state: LoginItemState) {
        self.state = state
    }

    func setEnabled(_ isEnabled: Bool) throws {
        if let error { throw error }
        state = isEnabled ? stateAfterEnable : .disabled
    }

    func openSystemSettings() {
        settingsOpenCount += 1
    }
}

private struct LoginItemFailure: Error {}

@MainActor
struct StatusMenuControllerTests {
    private let suiteName = "com.claudeusagebar.tests.\(UUID().uuidString)"

    @Test func menuContainsSpecifiedItems() throws {
        try withDefaults { defaults in
            let controller = makeController(FakeLoginItem(state: .disabled), defaults: defaults)

            let titles = controller.menu.items.filter { !$0.isSeparatorItem }.map(\.title)
            #expect(titles == ["새로고침", "로그인 시 실행", "갱신 간격", "종료"])
            #expect(intervalItems(controller).map(\.title) == ["1분", "5분", "10분", "15분"])
        }
    }

    @Test func defaultIntervalIsChecked() throws {
        try withDefaults { defaults in
            let controller = makeController(FakeLoginItem(state: .disabled), defaults: defaults)

            #expect(checkedInterval(controller) == "5분")
        }
    }

    @Test func selectingIntervalPersistsAndNotifies() throws {
        try withDefaults { defaults in
            var received: TimeInterval?
            let controller = makeController(
                FakeLoginItem(state: .disabled),
                defaults: defaults,
                onInterval: { received = $0 }
            )

            controller.selectPollInterval(600)

            #expect(received == 600)
            #expect(PollingSettings(defaults: defaults).interval == 600)
            #expect(checkedInterval(controller) == "10분")
        }
    }

    @Test(arguments: [0.0, 59.0, 901.0])
    func invalidStoredIntervalFallsBack(stored: Double) throws {
        try withDefaults { defaults in
            defaults.set(stored, forKey: Constants.Polling.intervalKey)

            #expect(PollingSettings(defaults: defaults).interval == 300)
        }
    }

    @Test func togglesLoginItem() throws {
        try withDefaults { defaults in
            let loginItem = FakeLoginItem(state: .disabled)
            let controller = makeController(loginItem, defaults: defaults)

            controller.toggleLoginItem()
            #expect(loginItem.state == .enabled)
            #expect(loginMenuItem(controller).state == .on)

            controller.toggleLoginItem()
            #expect(loginItem.state == .disabled)
            #expect(loginMenuItem(controller).state == .off)
        }
    }

    @Test func approvalRequirementOpensSystemSettings() throws {
        try withDefaults { defaults in
            let loginItem = FakeLoginItem(state: .disabled)
            loginItem.stateAfterEnable = .requiresApproval
            let controller = makeController(loginItem, defaults: defaults)

            controller.toggleLoginItem()

            #expect(loginItem.settingsOpenCount == 1)
            #expect(loginMenuItem(controller).state == .mixed)
        }
    }

    @Test func loginItemFailureIsReported() throws {
        try withDefaults { defaults in
            let loginItem = FakeLoginItem(state: .disabled)
            loginItem.error = LoginItemFailure()
            var errorCount = 0
            let controller = makeController(
                loginItem,
                defaults: defaults,
                onError: { errorCount += 1 }
            )

            controller.toggleLoginItem()

            #expect(errorCount == 1)
            #expect(loginMenuItem(controller).state == .off)
        }
    }

    private func makeController(
        _ loginItem: FakeLoginItem,
        defaults: UserDefaults,
        onInterval: @escaping (TimeInterval) -> Void = { _ in },
        onError: @escaping @MainActor () -> Void = {}
    ) -> StatusMenuController {
        StatusMenuController(
            loginItem: loginItem,
            pollingSettings: PollingSettings(defaults: defaults),
            onRefresh: {},
            onPollIntervalChange: onInterval,
            onLoginItemError: onError
        )
    }

    private func loginMenuItem(_ controller: StatusMenuController) -> NSMenuItem {
        controller.menu.items.first { $0.title == "로그인 시 실행" } ?? NSMenuItem()
    }

    private func intervalItems(_ controller: StatusMenuController) -> [NSMenuItem] {
        controller.menu.items.first { $0.title == "갱신 간격" }?.submenu?.items ?? []
    }

    private func checkedInterval(_ controller: StatusMenuController) -> String? {
        intervalItems(controller).first { $0.state == .on }?.title
    }

    private func withDefaults(_ body: (UserDefaults) throws -> Void) throws {
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        try body(defaults)
    }
}
