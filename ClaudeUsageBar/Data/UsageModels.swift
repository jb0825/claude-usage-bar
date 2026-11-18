import Foundation

// 비공식 엔드포인트라 형식이 바뀔 수 있다. 필드 하나의 타입이 달라져도 나머지 값은 살리도록
// 필드별로 실패를 흡수한다.
struct UsageResponseDTO: Decodable, Sendable {
    let fiveHour: UsageWindowDTO?
    let sevenDay: UsageWindowDTO?

    private enum CodingKeys: String, CodingKey {
        case fiveHour = "five_hour"
        case sevenDay = "seven_day"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        fiveHour = try? container.decodeIfPresent(UsageWindowDTO.self, forKey: .fiveHour)
        sevenDay = try? container.decodeIfPresent(UsageWindowDTO.self, forKey: .sevenDay)
    }
}

struct UsageWindowDTO: Decodable, Sendable {
    let utilization: Double?
    let resetsAt: String?

    private enum CodingKeys: String, CodingKey {
        case utilization
        case resetsAt = "resets_at"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        utilization = try? container.decodeIfPresent(Double.self, forKey: .utilization)
        resetsAt = try? container.decodeIfPresent(String.self, forKey: .resetsAt)
    }
}

struct UsageWindow: Codable, Equatable, Sendable {
    enum Reset: Codable, Equatable, Sendable {
        case noActiveSession
        case at(Date)
        case unknown
    }

    /// 현재 사용량(0~100). 응답에서 값을 알 수 없으면 `nil`.
    let usedPercent: Int?
    let reset: Reset

    init(dto: UsageWindowDTO?) {
        guard let dto, let resetsAt = dto.resetsAt else {
            usedPercent = 0
            reset = .noActiveSession
            return
        }

        usedPercent = dto.utilization.map(Self.usedPercent(utilization:))
        reset = UsageDateParser.date(from: resetsAt).map { .at(Self.flooredToMinute($0)) } ?? .unknown
    }

    private init(usedPercent: Int?, reset: Reset) {
        self.usedPercent = usedPercent
        self.reset = reset
    }

    // 저장된 값의 초기화 시각이 지났으면 그 사용량은 더 이상 현재 값이 아니다.
    func clearingUsageIfReset(at date: Date) -> UsageWindow {
        guard case .at(let resetDate) = reset, resetDate <= date else { return self }
        return UsageWindow(usedPercent: nil, reset: reset)
    }

    private static func usedPercent(utilization: Double) -> Int {
        let maximum = Constants.Usage.maximumPercent
        let clamped = min(max(utilization, 0), maximum)
        return Int(clamped.rounded())
    }

    // 같은 초기화 시각도 응답마다 소수 초가 달라진다. 분 단위로 맞춰 불필요한 UI 갱신을 막는다.
    private static func flooredToMinute(_ date: Date) -> Date {
        let secondsPerMinute = Constants.Time.secondsPerMinute
        let minutes = (date.timeIntervalSince1970 / secondsPerMinute).rounded(.down)
        return Date(timeIntervalSince1970: minutes * secondsPerMinute)
    }
}

struct UsageSnapshot: Codable, Equatable, Sendable {
    let session: UsageWindow
    let weekly: UsageWindow
    let fetchedAt: Date

    init(response: UsageResponseDTO, fetchedAt: Date) {
        session = UsageWindow(dto: response.fiveHour)
        weekly = UsageWindow(dto: response.sevenDay)
        self.fetchedAt = fetchedAt
    }

    private init(session: UsageWindow, weekly: UsageWindow, fetchedAt: Date) {
        self.session = session
        self.weekly = weekly
        self.fetchedAt = fetchedAt
    }

    func clearingExpiredUsage(at date: Date) -> UsageSnapshot {
        UsageSnapshot(
            session: session.clearingUsageIfReset(at: date),
            weekly: weekly.clearingUsageIfReset(at: date),
            fetchedAt: fetchedAt
        )
    }

    static func decode(from data: Data, fetchedAt: Date) throws -> UsageSnapshot {
        let response = try JSONDecoder().decode(UsageResponseDTO.self, from: data)
        return UsageSnapshot(response: response, fetchedAt: fetchedAt)
    }
}

enum UsageDateParser {
    // 실제 응답은 소수 6자리 초를 포함하지만, 형식 변화에 대비해 소수 없는 값도 받는다.
    static func date(from string: String) -> Date? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        if let date = formatter.date(from: string) {
            return date
        }

        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.date(from: string)
    }
}
