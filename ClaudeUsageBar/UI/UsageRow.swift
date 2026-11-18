import AppKit
import SwiftUI

struct UsageRowModel: Equatable {
    let title: String
    let percentText: String
    let progressValue: Double
    let tone: StatusTitle.Tone
    let resetText: String
    let accessibilityLabel: String

    init(
        title: String,
        window: UsageWindow?,
        showsRelativeTime: Bool,
        now: Date,
        formatter: ResetTimeFormatter
    ) {
        let value = StatusTitle.Value(
            usedPercent: window?.usedPercent,
            hasFailure: false
        )
        let used = window?.usedPercent

        self.title = title
        percentText = String(localized: "\(value.text) 사용")
        progressValue = Double(used ?? 0)
        tone = value.tone
        resetText = Self.resetText(
            for: window?.reset,
            showsRelativeTime: showsRelativeTime,
            now: now,
            formatter: formatter
        )

        let spokenUsage = used.map { String(localized: "\($0)퍼센트 사용") }
            ?? String(localized: "사용량 알 수 없음")
        let spokenReset = Self.spokenReset(for: window?.reset, now: now, formatter: formatter)
        accessibilityLabel = String(localized: "\(title) \(spokenUsage), \(spokenReset)")
    }

    private static func resetText(
        for reset: UsageWindow.Reset?,
        showsRelativeTime: Bool,
        now: Date,
        formatter: ResetTimeFormatter
    ) -> String {
        switch reset {
        case .at(let date):
            let absolute = formatter.absoluteString(for: date, now: now)
            // 지난 시각은 값이 오래됐다는 뜻이므로 주간 항목에서도 상태를 함께 보여준다.
            guard showsRelativeTime || date <= now else {
                return String(localized: "초기화 · \(absolute)")
            }
            let relative = formatter.relativeString(for: date, now: now)
            return String(localized: "초기화 · \(absolute) \(relative)")
        case .noActiveSession:
            return String(localized: "세션 없음")
        case .unknown:
            return String(localized: "초기화 시간 알 수 없음")
        case nil:
            return String(localized: "데이터 없음")
        }
    }

    private static func spokenReset(
        for reset: UsageWindow.Reset?,
        now: Date,
        formatter: ResetTimeFormatter
    ) -> String {
        switch reset {
        case .at(let date) where date <= now:
            return String(localized: "초기화됨, 갱신 대기")
        case .at(let date):
            let spoken = formatter.accessibilityString(for: date, now: now)
            return String(localized: "\(spoken) 초기화")
        case .noActiveSession:
            return String(localized: "세션 없음")
        case .unknown:
            return String(localized: "초기화 시간 알 수 없음")
        case nil:
            return String(localized: "데이터 없음")
        }
    }
}

struct UsageRow: View {
    let model: UsageRowModel

    var body: some View {
        VStack(alignment: .leading, spacing: Constants.Popover.rowSpacing) {
            HStack(alignment: .firstTextBaseline) {
                Text(model.title)
                    .font(.body.weight(.semibold))
                Spacer()
                Text(model.percentText)
                    .font(.body.monospacedDigit())
            }

            ProgressView(value: model.progressValue, total: Constants.Usage.maximumPercent)
                .progressViewStyle(.linear)
                .tint(tint)

            Text(model.resetText)
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(model.accessibilityLabel)
    }

    private var tint: Color {
        switch model.tone {
        case .normal, .muted: .accentColor
        case .warning: Color(nsColor: .systemOrange)
        case .critical: Color(nsColor: .systemRed)
        }
    }
}
