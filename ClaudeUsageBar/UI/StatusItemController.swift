import AppKit
import Observation
import SwiftUI

struct StatusTitle: Equatable {
    enum Tone: Equatable {
        case normal
        case warning
        case critical
        case muted
    }

    struct Value: Equatable {
        let text: String
        let tone: Tone

        init(usedPercent: Int?, hasFailure: Bool) {
            text = usedPercent.map { "\($0)%" } ?? "–%"
            tone = hasFailure ? .muted : Self.tone(for: usedPercent)
        }

        private static func tone(for usedPercent: Int?) -> Tone {
            guard let usedPercent else { return .normal }
            if usedPercent >= Constants.Usage.criticalThreshold { return .critical }
            if usedPercent >= Constants.Usage.warningThreshold { return .warning }
            return .normal
        }
    }

    let session: Value
    let weekly: Value

    init(snapshot: UsageSnapshot?, failure: RefreshFailure?) {
        let hasFailure = failure != nil
        session = Value(
            usedPercent: snapshot?.session.usedPercent,
            hasFailure: hasFailure
        )
        weekly = Value(
            usedPercent: snapshot?.weekly.usedPercent,
            hasFailure: hasFailure
        )
    }
}

@MainActor
final class StatusItemController: NSObject, NSPopoverDelegate {
    private let store: UsageStore
    private let onRefresh: () -> Void
    private let onPopoverOpen: () -> Void
    private let contextMenu: NSMenu
    private let statusItem: NSStatusItem
    private var popover: NSPopover?
    private var lastPopoverCloseTime: TimeInterval?
    private var renderedTitle: StatusTitle?

    init(
        store: UsageStore,
        contextMenu: NSMenu,
        onRefresh: @escaping () -> Void,
        onPopoverOpen: @escaping () -> Void
    ) {
        self.store = store
        self.contextMenu = contextMenu
        self.onRefresh = onRefresh
        self.onPopoverOpen = onPopoverOpen
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        super.init()

        // Claude 종료로 숨겼다가 다시 표시해도 사용자가 옮긴 메뉴바 위치를 유지한다.
        statusItem.autosaveName = Constants.StatusItem.autosaveName
        configureButton()
        observeStore()
    }

    func popoverDidClose(_ notification: Notification) {
        lastPopoverCloseTime = ProcessInfo.processInfo.systemUptime
        // 닫힌 동안 SwiftUI 뷰와 타이머가 메모리에 남지 않게 해제한다.
        popover = nil
    }

    private func configureButton() {
        guard let button = statusItem.button else { return }
        button.target = self
        button.action = #selector(statusItemClicked)
        button.sendAction(on: [.leftMouseUp, .rightMouseUp])
    }

    @objc private func statusItemClicked() {
        guard let event = NSApp.currentEvent else { return }
        let opensMenu = event.type == .rightMouseUp || event.modifierFlags.contains(.control)
        if opensMenu {
            showContextMenu()
        } else {
            togglePopover()
        }
    }

    private func togglePopover() {
        if let popover {
            popover.performClose(nil)
        } else if !wasPopoverJustClosed {
            showPopover()
        }
    }

    // transient 팝오버는 버튼을 누르는 순간 먼저 닫히므로, 같은 클릭으로 다시 열리지 않게 막는다.
    private var wasPopoverJustClosed: Bool {
        guard let lastPopoverCloseTime else { return false }
        let elapsed = ProcessInfo.processInfo.systemUptime - lastPopoverCloseTime
        return elapsed < Constants.Popover.reopenGuardInterval
    }

    private func showPopover() {
        guard let button = statusItem.button else { return }

        let rootView = PopoverView(
            store: store,
            formatter: ResetTimeFormatter(),
            onRefresh: onRefresh,
            onQuit: { NSApp.terminate(nil) }
        )
        let hostingController = NSHostingController(rootView: rootView)
        hostingController.sizingOptions = [.preferredContentSize]

        let popover = NSPopover()
        popover.behavior = .transient
        popover.animates = true
        popover.delegate = self
        popover.contentViewController = hostingController
        self.popover = popover

        // NSApp.activate()만으로는 macOS가 활성화를 보류해 팝오버가 비활성 창으로 남는다.
        // 창을 key로 지정해야 첫 클릭부터 활성 표시가 되고 바깥 클릭으로 닫힌다.
        NSApp.activate()
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        popover.contentViewController?.view.window?.makeKey()
        onPopoverOpen()
    }

    // 메뉴를 계속 연결해 두면 좌클릭도 메뉴를 열기 때문에 표시하는 동안만 연결한다.
    private func showContextMenu() {
        popover?.performClose(nil)
        statusItem.menu = contextMenu
        statusItem.button?.performClick(nil)
        statusItem.menu = nil
    }

    private func observeStore() {
        withObservationTracking {
            render()
        } onChange: { [weak self] in
            Task { @MainActor in
                self?.observeStore()
            }
        }
    }

    private func render() {
        if statusItem.isVisible != store.isActive {
            statusItem.isVisible = store.isActive
        }
        if !store.isActive {
            popover?.performClose(nil)
        }

        let title = StatusTitle(snapshot: store.snapshot, failure: store.failure)
        guard title != renderedTitle else { return }

        statusItem.button?.attributedTitle = attributedString(for: title)
        renderedTitle = title
    }

    private func attributedString(for title: StatusTitle) -> NSAttributedString {
        let result = NSMutableAttributedString()
        result.append(segment(title.session.text, color: color(for: title.session.tone)))
        // 일반 공백은 메뉴바 글꼴에서 좁아 보여 가운뎃점 양옆에 en space를 쓴다.
        result.append(segment(String(localized: "\u{2002}·\u{2002}주간 "), color: .labelColor))
        result.append(segment(title.weekly.text, color: color(for: title.weekly.tone)))
        return result
    }

    private func segment(_ text: String, color: NSColor) -> NSAttributedString {
        NSAttributedString(
            string: text,
            attributes: [
                .font: NSFont.monospacedDigitSystemFont(
                    ofSize: Constants.StatusItem.fontSize,
                    weight: .medium
                ),
                .foregroundColor: color,
            ]
        )
    }

    private func color(for tone: StatusTitle.Tone) -> NSColor {
        switch tone {
        case .normal: .labelColor
        case .warning: .systemOrange
        case .critical: .systemRed
        case .muted: .secondaryLabelColor
        }
    }
}
