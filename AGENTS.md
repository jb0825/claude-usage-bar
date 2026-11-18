# AGENTS.md — ClaudeUsageBar

이 문서는 이 저장소에서 작업하는 코딩 에이전트를 위한 지침이다. 코드를 작성하기 전에 끝까지 읽고, 여기 적힌 규칙이 일반적인 관례와 충돌하면 이 문서를 따른다.

---

## 1. 프로젝트 개요

macOS 상단 메뉴바에 Claude 사용량(5시간 세션 사용량, 주간 사용량)을 표시하는 **초경량 네이티브 앱**.

- 표시 형식: `21% · 주간 74%` (숫자는 **현재 사용량** = `utilization`)
- 클릭 시 Apple HIG를 따르는 작은 팝오버가 상태바 아래에 열리고, 현재 세션/주간 사용량을 막대 바로, 각 초기화 날짜·시간을 함께 표시
- Claude 앱이 실행 중일 때만 표시·동작하고, Claude가 종료되면 숨김 + 완전 대기
- 최우선 가치: **가벼움(메모리/CPU 영향 최소)** > 정확성 > 기능 수

## 2. 핵심 요구사항 (변경 금지)

1. Claude 앱 실행 시 함께 활성화, Claude 종료 시 함께 비활성화
2. 상단바에 `n%`, `주간 n%` 표시 (n = 현재 사용량), 아이콘 없이 텍스트만 표시
3. 메모리·CPU 영향이 거의 없을 것
4. Claude 실행 중 사용량 추적. 상시 고빈도 폴링 대신 **프롬프트 전송/응답 완료 시점 갱신 + 저빈도 폴링** 하이브리드
5. 메뉴바에만 존재(Dock 아이콘 없음). 클릭 시 팝오버: 현재·주간 사용량 막대 바 + 현재·주간 초기화 시간 및 날짜

## 3. 기술 스택 및 제약

| 항목 | 결정 |
|---|---|
| 언어 | Swift 5.10+ (Swift 6 strict concurrency 호환 목표) |
| UI | AppKit `NSStatusItem` + `NSPopover` 안에 SwiftUI 뷰 |
| 최소 OS | macOS 14 Sonoma (`@Observable`, `SMAppService` 사용) |
| 프레임워크 | Foundation, AppKit, SwiftUI, Security, ServiceManagement, Darwin(notify), os(`Logger`) **만** 사용. 테스트 타깃은 Testing 추가 허용 |
| 외부 의존성 | **금지.** SPM/CocoaPods 패키지 추가하지 말 것 |
| 앱 형태 | 빌드 설정 `INFOPLIST_KEY_LSUIElement = YES`로 생성된 `Info.plist`에 `LSUIElement` 포함 |
| 샌드박스 | **끔** (다른 앱의 키체인 항목 접근이 필요). Hardened Runtime은 켬 |
| 배포 | 로컬 빌드 / Developer ID 서명. Mac App Store 대상 아님 |

금지 기술: Electron, Python, SwiftBar/xbar 플러그인, WebView, Combine 기반 상시 타이머, `Timer.scheduledTimer`의 1초 반복 루프.

## 4. 데이터 소스

### 4.1 엔드포인트

```
GET https://api.anthropic.com/api/oauth/usage
Authorization: Bearer <accessToken>
anthropic-beta: oauth-2025-04-20
Accept: application/json
```

- Claude Code가 내부적으로 쓰는 **비공식·비문서화** 엔드포인트다. 형식이 바뀔 수 있다고 가정하고 방어적으로 구현한다.
- 1단계 실측(2026-11-18): `anthropic-beta` 헤더가 없어도 200과 같은 구조의 응답을 받았다. 다만 비공식 API의 동작이 바뀔 수 있으므로 앱은 헤더를 계속 보낸다.

### 4.2 응답 (예시, 필드는 모두 선택적으로 취급)

```json
{
  "five_hour":        { "utilization": 21.0, "resets_at": "2026-11-18T12:40:00+00:00" },
  "seven_day":        { "utilization": 74.0, "resets_at": "2026-11-21T00:00:00+00:00" },
  "seven_day_sonnet": { "utilization": 3.0,  "resets_at": "..." },
  "seven_day_opus":   null,
  "extra_usage":      { "is_enabled": false }
}
```

- `five_hour` → 현재 세션, `seven_day` → 주간. MVP는 이 두 개만 표시한다.
- 모든 필드는 `Optional`로 디코딩한다. 모르는 키는 무시한다(`Codable` 기본 동작 유지, `CodingKeys`에 없는 키로 실패하지 않게).
- `resets_at == null` 또는 `five_hour == null` → 활성 세션 없음으로 보고 `0%`, 초기화 시간 대신 "세션 없음" 표시.
- `utilization`은 0~100 범위로 clamp해 사용량으로 쓴다. 표시는 반올림 정수.
- 날짜 파싱: `ISO8601DateFormatter`에 `.withInternetDateTime` 사용, 실패 시 `.withFractionalSeconds` 추가해 재시도.
- 1단계 실측(2026-11-18, `Tests/Fixtures/real-sample.json`에는 앱이 쓰는 필드만 보관):
  - `resets_at`은 `2026-11-18T13:20:00.467036+00:00`처럼 소수 6자리를 포함하며, 위 재시도 방식으로 파싱된다.
  - 같은 초기화 시각이어도 소수 부분은 응답마다 달라진다. 변경 여부는 **분 단위**로 비교한다.
  - `utilization`은 정수로 왔다. `Double`로 디코딩한다.
  - 최상위에 `limits`, `spend`, `seven_day_breakdown`과 용도를 알 수 없는 null 키가 다수 있다. MVP에서는 모두 무시한다.

### 4.3 인증 토큰

- 출처: macOS 로그인 키체인, generic password, service = `Claude Code-credentials`
- 값은 JSON 문자열이다. `claudeAiOauth.accessToken`을 사용한다(`expiresAt`도 읽어 둔다. 1단계 실측: epoch 밀리초 숫자).
- `SecItemCopyMatching`으로 읽고 **메모리에만 캐시**한다. 디스크·로그·UserDefaults에 절대 쓰지 않는다.
- 401 수신 시: 캐시를 버리고 키체인을 **한 번만** 다시 읽어 재시도. 그래도 401이면 오류 상태로 전환하고 다음 트리거까지 대기.

### 4.4 절대 하지 말 것

- ❌ 토큰 refresh 요청을 직접 보내는 것. refresh token이 교체되면 Claude Code가 로그아웃될 수 있다. 갱신은 Claude Code에 맡긴다.
- ❌ 키체인 항목에 **쓰기**.
- ❌ 토큰 값을 `print`/`os_log`/크래시 리포트에 남기는 것. 로그에는 `token=<redacted>`만.
- ❌ 이 엔드포인트 외의 Anthropic API 호출(메시지 API 등). 사용량을 소모하는 호출은 금지.
- ❌ 60초 미만 간격의 자동 반복 호출. 사용자가 직접 누른 수동 새로고침만 예외.

## 5. 아키텍처

```
ClaudeAppWatcher ──(launch/terminate)──▶ AppCoordinator ◀──(Darwin notify)── HookBridge
                                              │
                                              ▼
                     UsageService ──▶ CredentialStore (Keychain, in-memory cache)
                                              │
                                              ▼
                     UsageStore (@Observable, @MainActor)
                         │                         │
               StatusItemController           PopoverView (SwiftUI)
```

### 5.1 파일 구성

```
ClaudeUsageBar/
├─ App/
│  ├─ ClaudeUsageBarApp.swift      // @main, NSApplicationDelegateAdaptor
│  ├─ AppDelegate.swift            // 구성 요소 조립만 담당
│  ├─ AppCoordinator.swift         // 상태 머신 (idle ↔ active), 갱신 스케줄링
│  ├─ RefreshScheduler.swift       // 디바운스·백오프 규칙, 지연 실행
│  ├─ PollTimer.swift              // 폴링 DispatchSourceTimer
│  ├─ PollingSettings.swift        // 갱신 간격 저장
│  └─ Constants.swift              // 간격, 임계값, 엔드포인트 등 상수
├─ System/
│  ├─ ClaudeAppWatcher.swift       // NSWorkspace 실행/종료 감지
│  ├─ HookBridge.swift             // notify_register_dispatch 래퍼
│  ├─ LoginItemController.swift    // SMAppService 로그인 시 실행
│  └─ PowerObserver.swift          // sleep/wake 감지
├─ Data/
│  ├─ CredentialStore.swift        // 키체인 읽기 (actor)
│  ├─ UsageService.swift           // 네트워크 + 백오프 (actor)
│  ├─ UsageModels.swift            // Codable DTO + 도메인 모델
│  ├─ UsageCache.swift             // 마지막 사용량·조회 시각 저장 (토큰 제외)
│  └─ UsageStore.swift             // UI 상태 (@Observable, @MainActor)
├─ UI/
│  ├─ StatusItemController.swift   // NSStatusItem, 타이틀/색, 클릭·우클릭
│  ├─ StatusMenuController.swift   // 우클릭 메뉴
│  ├─ PopoverView.swift            // 팝오버 루트
│  ├─ UsageRow.swift               // 제목 + 막대 + 초기화 정보 한 줄 컴포넌트
│  └─ ResetTimeFormatter.swift     // 날짜/상대시간 한국어 포맷
├─ Resources/
│  └─ Assets.xcassets              // AccentColor

Tests/                             // 저장소 최상위. ClaudeUsageBar/ 폴더는 통째로 앱 타깃에 포함되므로 분리
├─ AppConfigurationTests.swift     // LSUIElement, bundle ID
├─ UsageModelsTests.swift          // fixture JSON 디코딩
├─ ResetTimeFormatterTests.swift
├─ CoordinatorDebounceTests.swift
├─ CredentialStoreTests.swift
├─ UsageServiceTests.swift
├─ AppCoordinatorTests.swift
├─ ClaudeAppWatcherTests.swift
├─ StatusTitleTests.swift
├─ StatusMenuControllerTests.swift
├─ UsageRowModelTests.swift
├─ UsageCacheTests.swift
├─ TestDoubles.swift               // 키체인, 네트워크, 서비스 목
└─ Fixtures/*.json                 // 정상, null 세션, 모르는 키 포함, 잘못된 날짜
```

### 5.2 상태 머신 (AppCoordinator)

```
        Claude launch / 앱 시작 시 Claude가 이미 실행 중
 idle ───────────────────────────────────────────────▶ active
  ▲                                                     │
  └──────────────── Claude terminate (모든 인스턴스) ────┘
```

- **idle**: 상태바 항목 `isVisible = false`, 폴링 타이머 해제, 진행 중 요청 취소, hook 신호 무시. CPU 0%가 목표.
- **active**: 상태바 항목 표시, 즉시 1회 갱신, 폴링 타이머 시작, hook 신호 수신.
- 앱 시작 시 `NSWorkspace.shared.runningApplications`로 Claude 실행 여부를 확인해 초기 상태를 결정한다.
- 앱 프로세스 자체는 종료하지 않는다(종료하면 다음 실행을 감지할 주체가 사라짐). 사용자가 메뉴에서 "종료"를 누를 때만 종료.

### 5.3 Claude 앱 감지

- 대상 bundle ID는 상수 배열로 관리: `["com.anthropic.claudefordesktop"]` (사용자 확인 완료)
- `NSWorkspace.shared.notificationCenter`의 `didLaunchApplicationNotification`, `didTerminateApplicationNotification`만 사용한다. **폴링으로 프로세스 목록을 확인하지 않는다.**
- terminate 시 동일 bundle ID 인스턴스가 남아 있는지 확인 후 idle 전환.

### 5.4 Claude Code hook 연동

사용자는 `~/.claude/settings.json`에 아래를 추가한다(앱이 이 파일을 자동 수정하지 않는다. README에 안내만).

```json
{
  "hooks": {
    "UserPromptSubmit": [{ "hooks": [{ "type": "command",
      "command": "notifyutil -p com.claudeusagebar.refresh" }] }],
    "Stop": [{ "hooks": [{ "type": "command",
      "command": "notifyutil -p com.claudeusagebar.refresh" }] }]
  }
}
```

- 앱은 `notify_register_dispatch("com.claudeusagebar.refresh", ...)`로 수신한다. 알림 이름은 상수 하나로 관리.
- 수신 시 `requestRefresh(reason: .hook)` 호출 → 디바운스 규칙(6.2) 적용.
- 등록 토큰은 앱 종료 시 `notify_cancel`.

## 6. 갱신 정책

### 6.1 트리거

| 트리거 | 동작 |
|---|---|
| idle → active 전환 | 즉시 갱신. 단 앱 재시작을 포함해 최근 60초 안에 조회했으면 60초 경과 시 갱신 |
| hook 신호 (`UserPromptSubmit`, `Stop`) | 디바운스 후 갱신 |
| 폴링 타이머 | 기본 300초 (설정 60~900초) |
| 시스템 wake | 즉시 갱신 1회 |
| 팝오버 열림 | 마지막 갱신이 60초 이상 지났으면 갱신 |
| 수동 새로고침 버튼 | 디바운스 무시, 단 진행 중 요청이 있으면 무시 |

### 6.2 디바운스·백오프

- 마지막 **성공 또는 시도** 후 60초 이내의 자동 트리거는 1회로 합친다(trailing 방식: 60초 경과 시점에 1회 실행). 4.4의 최소 호출 간격과 맞춘 값이다.
- 동시에 1개 요청만. 진행 중이면 새 요청은 "완료 후 1회 더" 플래그만 세운다.
- 429 / 5xx / 네트워크 오류: 지수 백오프 60s → 120s → 240s … 최대 900s. `Retry-After` 헤더가 있으면 지수 백오프와 비교해 더 긴 값을 쓴다(실측: 429에 `Retry-After: 0`이 올 수 있음).
- 백오프가 끝나면 자동으로 1회 재시도한다. 백오프 중에는 활성화·wake 트리거도 대기하고, 수동 새로고침만 예외다.
- 401·인증 정보 오류·기타 4xx·응답 형식 오류는 백오프하지 않고 다음 트리거까지 대기한다.
- 성공 시 백오프 초기화.
- 마지막 사용량과 조회 시각은 `UserDefaults`에 저장해 재시작 시 복원한다. 토큰은 저장하지 않고, 초기화 시각이 지난 사용량은 복원하지 않는다.
- 요청 타임아웃 15초.

### 6.3 타이머 구현

- `DispatchSourceTimer`를 사용하고 `leeway`를 간격의 10% 이상(최소 30초)으로 준다.
- 상태바에는 카운트다운을 표시하지 않는다. 팝오버의 상대 시간은 **팝오버가 열려 있을 때만** 60초 간격으로 갱신(`TimelineView(.periodic(from:by: 60))`).
- sleep 시 타이머 suspend, wake 시 resume.

## 7. UI 명세

### 7.1 상태바

- `NSStatusItem(length: NSStatusItem.variableLength)`, `autosaveName` 설정으로 사용자가 ⌘드래그한 위치 유지
- 아이콘: 사용하지 않는다. 사용자 결정에 따라 상태바에는 텍스트만 표시한다.
- 타이틀: `"21% · 주간 74%"`(가운뎃점 양옆은 en space `U+2002`), 폰트 `NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .medium)`
- 색: 각 숫자를 **사용량 기준**으로 개별 적용
  - < 80%: 기본(`labelColor`)
  - ≥ 80%: `systemOrange`
  - ≥ 95%: `systemRed`
- 데이터 없음: `"–% · 주간 –%"`. 오류 지속 시 별도 경고 표시 없이 값만 흐리게(`secondaryLabelColor`).
- 값이 실제로 바뀌었을 때만 `attributedTitle` 재설정.
- 좌클릭: 팝오버 토글. 우클릭(또는 ⌃클릭): `NSMenu` — 새로고침, 로그인 시 실행 토글, 폴링 간격, 종료.

### 7.2 팝오버

```
┌───────────────────────────────┐
│  Claude 사용량                 │
│ ────────────────────────────── │
│  현재 세션            21% 사용 │
│  ████░░░░░░░░░░░░░░░░          │
│  초기화 · 오늘 21:40 (2시간 15분 후) │
│ ────────────────────────────── │
│  주간                 74% 사용 │
│  ███████████████░░░░░          │
│  초기화 · 11월 21일 (금) 09:00 │
│ ────────────────────────────── │
│  새로고침           17:24 갱신 │
│ ────────────────────────────── │
│  종료                          │
└───────────────────────────────┘
```

- `NSPopover`, `behavior = .transient`, `animates = true`, 상태바 버튼 기준 `.minY` 엣지.
- macOS 메뉴바 시스템 패널(배터리 등)의 구성을 따른다. 콘텐츠 폭 300pt, 좌우 여백 14pt, 섹션 사이는 여백이 같은 `Divider`, 섹션 상하 여백 10pt. 배경은 팝오버 기본 머티리얼 그대로(커스텀 배경색 금지).
- 팝오버 제목 `.headline`, 섹션 제목 `.body.weight(.semibold)`, 퍼센트 `.body.monospacedDigit()`, 초기화 정보 `.callout` + `.secondary`.
- 막대: `ProgressView(value: used, total: 100).progressViewStyle(.linear)`, tint는 7.1과 동일 규칙(기본 `.accentColor`). **막대는 사용량**을 채운다.
- 하단: 마우스를 올리면 `Capsule` + `.quaternary` 배경이 표시되는 메뉴 행 2개(바깥 여백 6pt). 새로고침 행 오른쪽에 마지막 갱신 시각(`HH:mm 갱신`), 진행 중이면 `ProgressView().controlSize(.small)`. 그 아래 `Divider`로 나눈 종료 행.
- 오류 배너(제목 아래 별도 섹션, `.body` + `.secondary`, SF Symbol `exclamationmark.triangle.fill` + `systemOrange`):
  - 토큰 없음/401: "Claude Code 로그인 정보를 읽을 수 없어요. 터미널에서 `claude`로 다시 로그인해 주세요."
  - 네트워크/서버: "업데이트가 지연되고 있어요. 마지막 값 표시 중."
- 다크/라이트 모드, 접근성(VoiceOver 라벨: "현재 세션 21퍼센트 사용, 오늘 오후 9시 40분 초기화") 지원.

### 7.3 날짜 포맷 (ResetTimeFormatter)

- 로케일 `ko_KR`, 시스템 시간대.
- 오늘: `오늘 21:40` / 내일: `내일 09:00` / 그 외: `11월 21일 (금) 09:00`
- 상대 시간: `DateComponentsFormatter`(`.full`, 시·분 단위)로 두 단위를 만들고 "후"를 붙인다 → `(2시간 15분 후)`. `RelativeDateTimeFormatter`는 한 단위만 출력하므로 쓰지 않는다. 1분 미만은 `(곧)`.
- 과거 시각(초기화가 지났는데 아직 갱신 전): `(초기화됨 · 갱신 대기)`.

## 8. 성능 예산 (완료 조건에 포함)

| 지표 | 목표 |
|---|---|
| 상주 메모리 (active, 팝오버를 열기 전) | ≤ 25 MB (Activity Monitor "메모리") |
| 상주 메모리 (팝오버를 연 상태와 닫은 뒤) | ≤ 35 MB (SwiftUI 팝오버 비용 반영. 열 때의 일시적 최고값은 제외) |
| idle 시 CPU | 0.0% (10분 관찰 평균) |
| active, 팝오버 닫힘 CPU | 평균 < 0.1% |
| 웨이크업 (Energy Impact) | "낮음", idle 시 사실상 0 |
| 네트워크 | 시간당 ≤ 12회 + hook 트리거분 |
| 앱 크기 | ≤ 5 MB |

Instruments(Allocations, Time Profiler, Energy Log)로 측정하고 결과를 PR 설명에 적는다.

## 9. 코딩 규칙

- 동시성: UI 상태는 `@MainActor`. `CredentialStore`, `UsageService`는 `actor`. `DispatchQueue.main.async` 남발 금지.
- 강제 언래핑(`!`), `try!` 금지(테스트 제외).
- 매직 넘버는 `enum Constants`에 모은다(간격, 임계값, bundle ID, 알림 이름, 엔드포인트).
- 로그: `os.Logger(subsystem: "com.claudeusagebar", category: ...)`. 민감 정보 금지, 기본 레벨 `.debug`/`.info`.
- 사용자에게 보이는 문자열은 전부 한국어. `String(localized:)` 사용(추후 다국어 대비).
- 함수는 한 가지 일만. 파일당 300줄 넘으면 분리 검토.
- 주석은 "왜"를 설명할 때만. 비공식 API·hook·키체인 관련 결정에는 반드시 근거 주석.
- 속도를 이유로 정리·최적화를 생략하지 않는다. 동작하는 코드 + 정리된 코드가 완료 기준이다.

## 10. 빌드·테스트

```bash
# 빌드
xcodebuild -project ClaudeUsageBar.xcodeproj -scheme ClaudeUsageBar -configuration Debug build

# 테스트
xcodebuild -project ClaudeUsageBar.xcodeproj -scheme ClaudeUsageBar test

# Claude bundle ID 확인
osascript -e 'id of app "Claude"'

# hook 신호 수동 발생
notifyutil -p com.claudeusagebar.refresh
```

- 단위 테스트는 네트워크·키체인 없이 돌아가야 한다. `UsageService`와 `CredentialStore`는 프로토콜로 추상화하고 테스트에서 목(mock) 주입.
- 실제 API 호출 테스트는 자동 테스트에 넣지 않는다.

## 11. 구현 단계 (순서대로, 단계마다 멈추고 보고)

0. **프로젝트 정비**: macOS 전용 설정, 샌드박스 끔, Hardened Runtime 켬, `LSUIElement`, 테스트 타깃, `.gitignore`.
1. **검증**: 키체인 읽기 + API 1회 호출하는 최소 코드(또는 CLI 타깃)로 실제 응답 JSON과 필요한 헤더 확인. 결과를 `Tests/Fixtures/real-sample.json`(토큰·식별 정보 제거)로 저장하고 이 문서 4장 갱신.
2. **모델·포맷터**: `UsageModels`, `ResetTimeFormatter` + 테스트.
3. **상태바 MVP**: `NSStatusItem` 표시 + 수동 새로고침 + 300초 폴링.
4. **생명주기**: `ClaudeAppWatcher`, `AppCoordinator` idle/active, sleep/wake.
5. **hook 연동**: `HookBridge`, 디바운스·백오프 + 테스트.
6. **팝오버 UI**: 7.2 명세대로, 오류 배너, 접근성.
7. **마무리**: 로그인 시 실행(`SMAppService.mainApp`), 우클릭 메뉴, README(설치·hook 설정·키체인 허용 안내), 성능 측정.

각 단계 끝에 빌드·테스트 통과를 확인하고, 변경 요약과 다음 단계 계획을 보고한 뒤 진행한다.

## 12. 완료 정의 (Definition of Done)

- [ ] 2장 요구사항 5개 모두 동작
- [ ] 4.4 금지 사항 위반 없음 (토큰 refresh 없음, 토큰 로그 없음)
- [ ] 8장 성능 예산 충족, 측정값 기록
- [ ] 외부 의존성 0개
- [ ] 모든 단위 테스트 통과, 경고 0개
- [ ] README에 설치, hook 설정, 키체인 "항상 허용" 안내, 비공식 API 주의 문구 포함

## 13. 에이전트 작업 원칙

- 사용자와의 대화·보고는 **한국어**로 한다.
- 불확실한 사항(엔드포인트 헤더, bundle ID, 응답 필드)은 추측으로 코드에 박지 말고, 1단계에서 확인하거나 사용자에게 묻는다.
- 이 문서의 결정을 바꿔야 할 이유가 생기면 코드를 먼저 바꾸지 말고, 이유와 대안을 제시해 승인을 받은 뒤 이 문서도 함께 갱신한다.
- 사용자 홈 디렉터리의 설정 파일(`~/.claude/settings.json` 등)은 직접 수정하지 않는다.
