import Foundation

enum Constants {
    enum API {
        static let usageEndpoint = "https://api.anthropic.com/api/oauth/usage"
        static let betaHeaderName = "anthropic-beta"
        // 헤더 없이도 응답했지만(1단계 실측), Claude Code와 같은 요청 형식을 유지한다.
        static let betaHeaderValue = "oauth-2025-04-20"
        static let requestTimeout: TimeInterval = 15
        static let rateLimitedStatus = 429
        static let serverErrorStatuses = 500..<600
        static let retryAfterHeaderName = "Retry-After"
        static let httpDateFormat = "EEE, dd MMM yyyy HH:mm:ss zzz"
        static let httpDateLocaleIdentifier = "en_US_POSIX"
    }

    enum Hook {
        static let notificationName = "com.claudeusagebar.refresh"
    }

    enum Refresh {
        static let minimumInterval: TimeInterval = 60
        static let backoffBase: TimeInterval = 60
        static let backoffMaximum: TimeInterval = 900
    }

    enum ClaudeApp {
        static let bundleIdentifiers: Set<String> = ["com.anthropic.claudefordesktop"]
    }

    enum Keychain {
        static let service = "Claude Code-credentials"
    }

    enum Polling {
        static let defaultInterval: TimeInterval = 300
        static let minimumLeeway: TimeInterval = 30
        static let leewayRatio = 0.1
        static let intervalKey = "pollInterval"
        static let intervalRange: ClosedRange<TimeInterval> = 60...900
        static let intervalOptions: [TimeInterval] = [60, 300, 600, 900]
    }

    enum Usage {
        static let maximumPercent = 100.0
        static let warningThreshold = 80
        static let criticalThreshold = 95
    }

    enum Time {
        static let secondsPerMilli = 0.001
        static let secondsPerMinute = 60.0
    }

    enum DateFormat {
        static let localeIdentifier = "ko_KR"
        static let time = "HH:mm"
        static let monthDayWeekdayTime = "M월 d일 (E) HH:mm"
        static let spokenHour = "a h시"
        static let spokenHourMinute = "a h시 m분"
        static let spokenMonthDayWeekday = "M월 d일 EEEE"
    }

    enum Popover {
        static let width = 300.0
        static let horizontalInset = 14.0
        static let titleTopPadding = 12.0
        static let titleBottomPadding = 8.0
        static let sectionVerticalPadding = 10.0
        static let rowSpacing = 6.0
        static let bannerSpacing = 6.0
        static let menuInset = 6.0
        static let menuRowHorizontalPadding = 8.0
        static let menuRowVerticalPadding = 3.0
        static let reopenGuardInterval: TimeInterval = 0.3
    }

    enum StatusItem {
        static let autosaveName = "ClaudeUsageBarStatusItem"
        static let fontSize = 12.0
    }

    enum Cache {
        static let usageStateKey = "usageState.v1"
    }

    enum Logging {
        static let subsystem = "com.claudeusagebar"
    }

    enum Environment {
        static let xcTestConfiguration = "XCTestConfigurationFilePath"
    }
}
