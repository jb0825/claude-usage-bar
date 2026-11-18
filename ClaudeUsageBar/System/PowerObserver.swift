import AppKit

@MainActor
protocol PowerMonitoring: AnyObject {
    func start(onSleep: @escaping () -> Void, onWake: @escaping () -> Void)
}

@MainActor
final class PowerObserver: NSObject, PowerMonitoring {
    private let workspace: NSWorkspace
    private var onSleep: (() -> Void)?
    private var onWake: (() -> Void)?

    init(workspace: NSWorkspace = .shared) {
        self.workspace = workspace
    }

    func start(onSleep: @escaping () -> Void, onWake: @escaping () -> Void) {
        guard self.onSleep == nil else { return }
        self.onSleep = onSleep
        self.onWake = onWake

        let center = workspace.notificationCenter
        center.addObserver(
            self,
            selector: #selector(systemWillSleep),
            name: NSWorkspace.willSleepNotification,
            object: nil
        )
        center.addObserver(
            self,
            selector: #selector(systemDidWake),
            name: NSWorkspace.didWakeNotification,
            object: nil
        )
    }

    @objc private func systemWillSleep(_ notification: Notification) {
        onSleep?()
    }

    @objc private func systemDidWake(_ notification: Notification) {
        onWake?()
    }
}
