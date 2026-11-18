import AppKit

struct RunningAppInfo: Equatable, Sendable {
    let bundleIdentifier: String?
    let processIdentifier: pid_t
    let isTerminated: Bool

    init(bundleIdentifier: String?, processIdentifier: pid_t, isTerminated: Bool) {
        self.bundleIdentifier = bundleIdentifier
        self.processIdentifier = processIdentifier
        self.isTerminated = isTerminated
    }

    init(_ application: NSRunningApplication) {
        bundleIdentifier = application.bundleIdentifier
        processIdentifier = application.processIdentifier
        isTerminated = application.isTerminated
    }
}

@MainActor
protocol ClaudeAppMonitoring: AnyObject {
    var isClaudeRunning: Bool { get }
    func start(onChange: @escaping (Bool) -> Void)
}

// 프로세스 목록을 폴링하지 않고 NSWorkspace 알림만 사용해 대기 중 CPU 사용을 없앤다.
@MainActor
final class ClaudeAppWatcher: NSObject, ClaudeAppMonitoring {
    private let workspace: NSWorkspace
    private let bundleIdentifiers: Set<String>
    private var onChange: ((Bool) -> Void)?

    init(
        workspace: NSWorkspace = .shared,
        bundleIdentifiers: Set<String> = Constants.ClaudeApp.bundleIdentifiers
    ) {
        self.workspace = workspace
        self.bundleIdentifiers = bundleIdentifiers
    }

    var isClaudeRunning: Bool {
        Self.containsClaude(
            in: workspace.runningApplications.map(RunningAppInfo.init),
            bundleIdentifiers: bundleIdentifiers
        )
    }

    func start(onChange: @escaping (Bool) -> Void) {
        guard self.onChange == nil else { return }
        self.onChange = onChange

        let center = workspace.notificationCenter
        center.addObserver(
            self,
            selector: #selector(applicationDidLaunch),
            name: NSWorkspace.didLaunchApplicationNotification,
            object: nil
        )
        center.addObserver(
            self,
            selector: #selector(applicationDidTerminate),
            name: NSWorkspace.didTerminateApplicationNotification,
            object: nil
        )
    }

    nonisolated static func containsClaude(
        in applications: [RunningAppInfo],
        bundleIdentifiers: Set<String>,
        excludingProcess excludedProcess: pid_t? = nil
    ) -> Bool {
        applications.contains { application in
            guard let bundleIdentifier = application.bundleIdentifier else { return false }
            return bundleIdentifiers.contains(bundleIdentifier)
                && !application.isTerminated
                && application.processIdentifier != excludedProcess
        }
    }

    @objc private func applicationDidLaunch(_ notification: Notification) {
        guard claudeApplication(from: notification) != nil else { return }
        onChange?(true)
    }

    @objc private func applicationDidTerminate(_ notification: Notification) {
        guard let application = claudeApplication(from: notification) else { return }

        // 종료 직후에는 목록에 해당 프로세스가 남아 있을 수 있어 명시적으로 제외한다.
        let isStillRunning = Self.containsClaude(
            in: workspace.runningApplications.map(RunningAppInfo.init),
            bundleIdentifiers: bundleIdentifiers,
            excludingProcess: application.processIdentifier
        )
        onChange?(isStillRunning)
    }

    private func claudeApplication(from notification: Notification) -> NSRunningApplication? {
        guard let application = notification.userInfo?[NSWorkspace.applicationUserInfoKey]
            as? NSRunningApplication,
            let bundleIdentifier = application.bundleIdentifier,
            bundleIdentifiers.contains(bundleIdentifier)
        else {
            return nil
        }
        return application
    }
}
