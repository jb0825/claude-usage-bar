import Foundation

struct ResetTimeFormatter {
    private let calendar: Calendar
    private let timeFormatter: DateFormatter
    private let dateTimeFormatter: DateFormatter
    private let spokenHourFormatter: DateFormatter
    private let spokenHourMinuteFormatter: DateFormatter
    private let spokenDayFormatter: DateFormatter
    private let durationFormatter: DateComponentsFormatter

    init(timeZone: TimeZone = .autoupdatingCurrent) {
        let locale = Locale(identifier: Constants.DateFormat.localeIdentifier)

        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = locale
        calendar.timeZone = timeZone
        self.calendar = calendar

        timeFormatter = Self.makeDateFormatter(
            format: Constants.DateFormat.time,
            calendar: calendar
        )
        dateTimeFormatter = Self.makeDateFormatter(
            format: Constants.DateFormat.monthDayWeekdayTime,
            calendar: calendar
        )
        spokenHourFormatter = Self.makeDateFormatter(
            format: Constants.DateFormat.spokenHour,
            calendar: calendar
        )
        spokenHourMinuteFormatter = Self.makeDateFormatter(
            format: Constants.DateFormat.spokenHourMinute,
            calendar: calendar
        )
        spokenDayFormatter = Self.makeDateFormatter(
            format: Constants.DateFormat.spokenMonthDayWeekday,
            calendar: calendar
        )

        let durationFormatter = DateComponentsFormatter()
        durationFormatter.calendar = calendar
        durationFormatter.allowedUnits = [.hour, .minute]
        durationFormatter.unitsStyle = .full
        self.durationFormatter = durationFormatter
    }

    func timeString(for date: Date) -> String {
        timeFormatter.string(from: date)
    }

    func absoluteString(for date: Date, now: Date) -> String {
        let time = timeFormatter.string(from: date)

        if isToday(date, now: now) {
            return String(localized: "오늘 \(time)")
        }
        if isTomorrow(date, now: now) {
            return String(localized: "내일 \(time)")
        }
        return dateTimeFormatter.string(from: date)
    }

    func accessibilityString(for date: Date, now: Date) -> String {
        let hasMinutes = calendar.component(.minute, from: date) != 0
        let time = (hasMinutes ? spokenHourMinuteFormatter : spokenHourFormatter).string(from: date)

        if isToday(date, now: now) {
            return String(localized: "오늘 \(time)")
        }
        if isTomorrow(date, now: now) {
            return String(localized: "내일 \(time)")
        }
        let day = spokenDayFormatter.string(from: date)
        return String(localized: "\(day) \(time)")
    }

    func relativeString(for date: Date, now: Date) -> String {
        let interval = date.timeIntervalSince(now)
        let secondsPerMinute = Constants.Time.secondsPerMinute

        guard interval > 0 else {
            return String(localized: "(초기화됨 · 갱신 대기)")
        }
        guard interval >= secondsPerMinute else {
            return String(localized: "(곧)")
        }

        // 남은 시간을 실제보다 길게 보여주지 않도록 분 미만은 버린다.
        let wholeMinutes = (interval / secondsPerMinute).rounded(.down)
        guard let duration = durationFormatter.string(from: wholeMinutes * secondsPerMinute) else {
            return String(localized: "(곧)")
        }
        return String(localized: "(\(duration) 후)")
    }

    private func isToday(_ date: Date, now: Date) -> Bool {
        calendar.isDate(date, inSameDayAs: now)
    }

    private func isTomorrow(_ date: Date, now: Date) -> Bool {
        guard let tomorrow = calendar.date(byAdding: .day, value: 1, to: now) else {
            return false
        }
        return calendar.isDate(date, inSameDayAs: tomorrow)
    }

    private static func makeDateFormatter(format: String, calendar: Calendar) -> DateFormatter {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.locale = calendar.locale
        formatter.timeZone = calendar.timeZone
        formatter.dateFormat = format
        return formatter
    }
}
