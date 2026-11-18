import AppKit
import SwiftUI

extension RefreshFailure {
    var bannerMessage: String {
        switch self {
        case .authentication:
            String(localized: "Claude Code 로그인 정보를 읽을 수 없어요. 터미널에서 `claude`로 다시 로그인해 주세요.")
        case .temporary:
            String(localized: "업데이트가 지연되고 있어요. 마지막 값 표시 중.")
        }
    }
}

struct PopoverView: View {
    let store: UsageStore
    let formatter: ResetTimeFormatter
    let onRefresh: () -> Void
    let onQuit: () -> Void

    var body: some View {
        // 뷰는 팝오버가 열려 있을 때만 존재하므로 상대 시간 갱신도 그동안만 돈다.
        TimelineView(.periodic(from: .now, by: Constants.Time.secondsPerMinute)) { context in
            content(now: context.date)
        }
    }

    private func content(now: Date) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(String(localized: "Claude 사용량"))
                .font(.headline)
                .padding(.horizontal, Constants.Popover.horizontalInset)
                .padding(.top, Constants.Popover.titleTopPadding)
                .padding(.bottom, Constants.Popover.titleBottomPadding)

            if let failure = store.failure {
                separator
                section {
                    banner(message: failure.bannerMessage)
                }
            }

            separator
            section {
                UsageRow(model: UsageRowModel(
                    title: String(localized: "현재 세션"),
                    window: store.snapshot?.session,
                    showsRelativeTime: true,
                    now: now,
                    formatter: formatter
                ))
            }

            separator
            section {
                UsageRow(model: UsageRowModel(
                    title: String(localized: "주간"),
                    window: store.snapshot?.weekly,
                    showsRelativeTime: false,
                    now: now,
                    formatter: formatter
                ))
            }

            separator
            menuSection {
                refreshButton
            }

            separator
            menuSection {
                quitButton
            }
        }
        .frame(width: Constants.Popover.width, alignment: .leading)
    }

    private var separator: some View {
        Divider()
            .padding(.horizontal, Constants.Popover.horizontalInset)
    }

    private func section(@ViewBuilder content: () -> some View) -> some View {
        content()
            .padding(.horizontal, Constants.Popover.horizontalInset)
            .padding(.vertical, Constants.Popover.sectionVerticalPadding)
    }

    private func banner(message: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: Constants.Popover.bannerSpacing) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(Color(nsColor: .systemOrange))
                .accessibilityHidden(true)
            // 안내 문구의 `claude` 명령을 코드 형식으로 표시한다.
            Text(LocalizedStringKey(message))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .font(.body)
    }

    private func menuSection(@ViewBuilder content: () -> some View) -> some View {
        content()
            .buttonStyle(MenuRowButtonStyle())
            .padding(Constants.Popover.menuInset)
    }

    private var refreshButton: some View {
        Button(action: onRefresh) {
            HStack {
                Text(String(localized: "새로고침"))
                Spacer()
                refreshStatus
            }
        }
        .disabled(store.isRefreshing)
    }

    private var quitButton: some View {
        Button(action: onQuit) {
            Text(String(localized: "종료"))
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    @ViewBuilder
    private var refreshStatus: some View {
        if store.isRefreshing {
            ProgressView()
                .controlSize(.small)
                .accessibilityLabel(String(localized: "새로고침 중"))
        } else {
            Text(lastUpdatedText)
                .font(.body.monospacedDigit())
                .foregroundStyle(.secondary)
        }
    }

    private var lastUpdatedText: String {
        guard let fetchedAt = store.snapshot?.fetchedAt else {
            return String(localized: "갱신 전")
        }
        let time = formatter.timeString(for: fetchedAt)
        return String(localized: "\(time) 갱신")
    }
}

// 시스템 메뉴바 패널의 하단 항목처럼 마우스를 올렸을 때만 배경을 표시한다.
private struct MenuRowButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        MenuRow(configuration: configuration)
    }

    private struct MenuRow: View {
        let configuration: Configuration
        @Environment(\.isEnabled) private var isEnabled
        @State private var isHovered = false

        var body: some View {
            configuration.label
                .font(.body)
                .foregroundStyle(isEnabled ? .primary : .secondary)
                .padding(.horizontal, Constants.Popover.menuRowHorizontalPadding)
                .padding(.vertical, Constants.Popover.menuRowVerticalPadding)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background {
                    // 고정 색 대신 시스템 계층 색을 써서 라이트·다크 모드와 배경에 맞춘다.
                    Capsule()
                        .fill(.quaternary)
                        .opacity(isHighlighted ? 1 : 0)
                }
                .contentShape(Capsule())
                .onHover { isHovered = $0 }
        }

        private var isHighlighted: Bool {
            isEnabled && (isHovered || configuration.isPressed)
        }
    }
}
