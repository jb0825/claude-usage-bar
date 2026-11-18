import Foundation
import Testing
@testable import ClaudeUsageBar

// 테스트는 앱을 호스트로 실행하므로 Bundle.main이 빌드된 앱 번들을 가리킨다.
struct AppConfigurationTests {
    @Test func hostedTestsDoNotStartServices() {
        let environment = ProcessInfo.processInfo.environment

        #expect(!AppDelegate.shouldStartServices(environment: environment))
    }

    @Test func appIsMenuBarOnly() {
        #expect(Bundle.main.object(forInfoDictionaryKey: "LSUIElement") as? Bool == true)
    }

    @Test func bundleIdentifierMatchesProject() {
        #expect(Bundle.main.bundleIdentifier == "com.claudeusagebar")
    }
}
