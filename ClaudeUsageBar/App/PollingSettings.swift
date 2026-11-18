import Foundation

struct PollingSettings {
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    var interval: TimeInterval {
        get {
            let stored = defaults.double(forKey: Constants.Polling.intervalKey)
            return Constants.Polling.intervalRange.contains(stored)
                ? stored
                : Constants.Polling.defaultInterval
        }
        nonmutating set {
            defaults.set(newValue, forKey: Constants.Polling.intervalKey)
        }
    }
}
