import ServiceManagement

enum LoginItemState: Equatable {
    case enabled
    case disabled
    case requiresApproval
}

@MainActor
protocol LoginItemControlling {
    var state: LoginItemState { get }
    func setEnabled(_ isEnabled: Bool) throws
    func openSystemSettings()
}

struct LoginItemController: LoginItemControlling {
    private let service = SMAppService.mainApp

    var state: LoginItemState {
        switch service.status {
        case .enabled:
            .enabled
        case .requiresApproval:
            .requiresApproval
        case .notRegistered, .notFound:
            .disabled
        @unknown default:
            .disabled
        }
    }

    func setEnabled(_ isEnabled: Bool) throws {
        if isEnabled {
            try service.register()
        } else {
            try service.unregister()
        }
    }

    func openSystemSettings() {
        SMAppService.openSystemSettingsLoginItems()
    }
}
