import Darwin
import Testing
@testable import ClaudeUsageBar

struct ClaudeAppWatcherTests {
    private let claudeID = "com.anthropic.claudefordesktop"

    @Test func detectsRunningClaude() {
        #expect(contains([app(claudeID, pid: 10)]))
    }

    @Test func ignoresOtherAndUnnamedApps() {
        #expect(!contains([app("com.example.other", pid: 10), app(nil, pid: 11)]))
    }

    @Test func ignoresTerminatedInstance() {
        #expect(!contains([app(claudeID, pid: 10, isTerminated: true)]))
    }

    @Test func excludedProcessDoesNotCount() {
        #expect(!contains([app(claudeID, pid: 10)], excluding: 10))
    }

    @Test func anotherInstanceKeepsClaudeRunning() {
        #expect(contains([app(claudeID, pid: 10), app(claudeID, pid: 11)], excluding: 10))
    }

    private func contains(_ apps: [RunningAppInfo], excluding pid: pid_t? = nil) -> Bool {
        ClaudeAppWatcher.containsClaude(
            in: apps,
            bundleIdentifiers: [claudeID],
            excludingProcess: pid
        )
    }

    private func app(_ id: String?, pid: pid_t, isTerminated: Bool = false) -> RunningAppInfo {
        RunningAppInfo(bundleIdentifier: id, processIdentifier: pid, isTerminated: isTerminated)
    }
}
