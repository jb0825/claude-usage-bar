import Foundation
@testable import ClaudeUsageBar

final class FakeKeychain: KeychainReading, @unchecked Sendable {
    private let lock = NSLock()
    private var results: [Result<Data, CredentialError>]
    private var reads = 0

    init(results: [Result<Data, CredentialError>]) {
        self.results = results
    }

    var readCount: Int {
        lock.withLock { reads }
    }

    func readCredentialData() throws -> Data {
        try lock.withLock {
            reads += 1
            let result = results.count > 1 ? results.removeFirst() : results[0]
            return try result.get()
        }
    }
}

actor FakeCredentials: CredentialProviding {
    private let current: AccessToken
    private let reloaded: AccessToken
    private(set) var reloadCount = 0

    init(current: String, reloaded: String) {
        self.current = AccessToken(value: current)
        self.reloaded = AccessToken(value: reloaded)
    }

    func currentToken() -> AccessToken {
        current
    }

    func reloadToken() -> AccessToken {
        reloadCount += 1
        return reloaded
    }
}

actor FakeTransport: HTTPTransport {
    private var responses: [Result<(Int, Data), URLError>]
    private let headerFields: [String: String]?
    private(set) var requests: [URLRequest] = []

    init(responses: [Result<(Int, Data), URLError>], headerFields: [String: String]? = nil) {
        self.responses = responses
        self.headerFields = headerFields
    }

    func send(_ request: URLRequest) throws -> (Data, HTTPURLResponse) {
        requests.append(request)
        let (status, data) = try responses.removeFirst().get()
        guard let url = request.url,
              let response = HTTPURLResponse(
                  url: url,
                  statusCode: status,
                  httpVersion: nil,
                  headerFields: headerFields
              )
        else {
            throw URLError(.badServerResponse)
        }
        return (data, response)
    }
}

actor FakeUsageService: UsageFetching {
    private var results: [Result<UsageSnapshot, UsageError>]
    private var gate: CheckedContinuation<Void, Never>?
    private let waitsForRelease: Bool
    private(set) var fetchCount = 0

    init(results: [Result<UsageSnapshot, UsageError>], waitsForRelease: Bool = false) {
        self.results = results
        self.waitsForRelease = waitsForRelease
    }

    func fetchUsage() async throws -> UsageSnapshot {
        fetchCount += 1
        if waitsForRelease {
            await withCheckedContinuation { gate = $0 }
        }
        return try results.removeFirst().get()
    }

    func release() async {
        while gate == nil {
            await Task.yield()
        }
        gate?.resume()
        gate = nil
    }
}

@MainActor
final class FakeClaudeMonitor: ClaudeAppMonitoring {
    var isClaudeRunning: Bool
    private var onChange: ((Bool) -> Void)?

    init(isClaudeRunning: Bool) {
        self.isClaudeRunning = isClaudeRunning
    }

    func start(onChange: @escaping (Bool) -> Void) {
        self.onChange = onChange
    }

    func send(isRunning: Bool) {
        isClaudeRunning = isRunning
        onChange?(isRunning)
    }
}

@MainActor
final class FakePowerMonitor: PowerMonitoring {
    private var onSleep: (() -> Void)?
    private var onWake: (() -> Void)?

    func start(onSleep: @escaping () -> Void, onWake: @escaping () -> Void) {
        self.onSleep = onSleep
        self.onWake = onWake
    }

    func sleep() {
        onSleep?()
    }

    func wake() {
        onWake?()
    }
}

@MainActor
final class FakeHookMonitor: HookMonitoring {
    private var onSignal: (() -> Void)?

    func start(onSignal: @escaping () -> Void) {
        self.onSignal = onSignal
    }

    func send() {
        onSignal?()
    }
}

@MainActor
final class FakeUsageCache: UsageStateCaching {
    private let initial: PersistedUsageState?
    private(set) var saved: [PersistedUsageState] = []

    init(initial: PersistedUsageState? = nil) {
        self.initial = initial
    }

    func load() -> PersistedUsageState? {
        initial
    }

    func save(_ state: PersistedUsageState) {
        saved.append(state)
    }
}

@MainActor
final class FakeClock {
    private(set) var now = Date(timeIntervalSince1970: 1_000_000)

    func advance(by interval: TimeInterval) {
        now = now.addingTimeInterval(interval)
    }
}

@MainActor
final class FakeDelayScheduler: DelayScheduling {
    private final class Token {}

    private struct Entry {
        let delay: TimeInterval
        let action: @MainActor () -> Void
        weak var token: Token?
    }

    private var entries: [Entry] = []

    var activeDelays: [TimeInterval] {
        entries.filter { $0.token != nil }.map(\.delay)
    }

    func schedule(after delay: TimeInterval, action: @escaping @MainActor () -> Void) -> AnyObject {
        let token = Token()
        entries.append(Entry(delay: delay, action: action, token: token))
        return token
    }

    func fireActive() {
        let active = entries.filter { $0.token != nil }
        active.forEach { $0.action() }
    }
}

enum TestData {
    static let usageJSON = Data("""
    {
      "five_hour": { "utilization": 21, "resets_at": "2026-11-18T12:40:00+00:00" },
      "seven_day": { "utilization": 74, "resets_at": "2026-11-21T00:00:00+00:00" }
    }
    """.utf8)

    static func snapshot(fetchedAt: Date = Date(timeIntervalSince1970: 0)) throws -> UsageSnapshot {
        try UsageSnapshot.decode(from: usageJSON, fetchedAt: fetchedAt)
    }

    static func credentialJSON(token: String, expiresAtMilliseconds: Double?) -> Data {
        let expiry = expiresAtMilliseconds.map { ", \"expiresAt\": \($0)" } ?? ""
        return Data("""
        { "claudeAiOauth": { "accessToken": "\(token)"\(expiry) } }
        """.utf8)
    }
}
