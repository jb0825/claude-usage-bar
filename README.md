# ClaudeUsageBar

macOS 메뉴바에 Claude의 현재 세션 사용량과 주간 사용량을 표시하는 가벼운 네이티브 앱입니다.

```text
48% · 주간 69%
```

- 숫자는 **현재까지 사용한 양**입니다.
- 왼쪽 클릭: 사용량 막대와 초기화 시각을 보여 주는 팝오버
- 오른쪽 클릭 또는 `⌃` 클릭: 새로고침, 로그인 시 실행, 갱신 간격, 종료
- Claude 앱이 실행 중일 때만 메뉴바에 표시됩니다.
- Dock 아이콘이 없고 외부 의존성이 없습니다.

## 요구 사항

- macOS 14 이상
- Xcode
- Claude 데스크톱 앱
- Claude Code 로그인 (`claude` 명령으로 로그인)

## 설치

```bash
xcodebuild -project ClaudeUsageBar.xcodeproj -scheme ClaudeUsageBar -configuration Release -derivedDataPath build build
```

```bash
cp -R build/Build/Products/Release/ClaudeUsageBar.app /Applications/
```

```bash
open /Applications/ClaudeUsageBar.app
```

메뉴바 위치는 `⌘`를 누른 채 항목을 드래그해 옮길 수 있습니다.

### 코드 서명

프로젝트 기본값은 임시(ad-hoc) 서명입니다. 임시 서명은 다시 빌드할 때마다 서명이 바뀌어 키체인 허용 창이 다시 나타나고, 로그인 시 실행이 제대로 동작하지 않을 수 있습니다. 계속 사용할 때는 Xcode의 Settings > Accounts에서 Apple Development 인증서를 만들고, 타깃의 Signing & Capabilities에서 팀과 인증서를 지정해 빌드하세요.

## 키체인 허용

앱은 Claude Code가 저장한 로그인 정보(`Claude Code-credentials`)를 읽어 사용량을 조회합니다. 처음 실행하면 macOS가 접근 허용을 묻습니다. 서명된 빌드를 설치했다면 **항상 허용**을 선택하면 다시 묻지 않습니다.

- 앱은 이 항목을 읽기만 하고 수정하지 않습니다.
- 토큰은 메모리에만 보관하며 디스크와 로그에 기록하지 않습니다.
- 토큰이 만료되어도 앱이 직접 갱신하지 않습니다. Claude Code를 사용하면 갱신됩니다.

## Claude Code hook 설정 (선택)

프롬프트 전송과 응답 완료 시점에 사용량을 갱신하려면 `~/.claude/settings.json`에 아래 내용을 추가하세요. 이미 `hooks`가 있으면 그 안에 합쳐야 합니다. 앱은 이 파일을 수정하지 않습니다.

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

신호에는 프롬프트나 응답 내용이 포함되지 않습니다. 자동 조회는 최소 60초 간격으로 합쳐지며, 타이머 허용 오차 때문에 최대 약 90초 늦을 수 있습니다.

## 갱신 방식

| 시점 | 동작 |
|---|---|
| Claude 실행 | 조회. 최근 60초 안에 조회했으면 60초 경과 후 |
| 주기 갱신 | 기본 5분, 메뉴에서 1·5·10·15분 선택 |
| hook 신호 | 60초 간격으로 합쳐서 조회 |
| Mac 깨어남 | 즉시 조회 |
| 팝오버 열기 | 마지막 조회가 60초 이상 지났으면 조회 |
| 새로고침 | 즉시 조회 |
| 429, 5xx, 네트워크 오류 | 60초부터 최대 900초까지 간격을 늘려 재시도 |

마지막 사용량과 조회 시각은 재시작 시 복원하기 위해 `UserDefaults`에 저장합니다. 토큰은 저장하지 않습니다.

## 비공식 API 주의

이 앱은 Claude Code가 사용하는 **비공식·비문서화 엔드포인트** `https://api.anthropic.com/api/oauth/usage`를 호출합니다.

- Anthropic이 지원하거나 보장하는 API가 아니며, 형식이 바뀌거나 예고 없이 중단될 수 있습니다.
- 호출이 많다고 판단되면 `429`를 받을 수 있습니다. 이 경우 마지막 값을 유지하고 나중에 다시 시도합니다.
- 이 조회는 모델을 실행하지 않습니다.
- Claude Code의 공식 상태줄 `rate_limits` 필드는 향후 대안이 될 수 있습니다.

## 개발

```bash
xcodebuild -project ClaudeUsageBar.xcodeproj -scheme ClaudeUsageBar test
```

```bash
notifyutil -p com.claudeusagebar.refresh
```

단위 테스트는 실제 키체인과 네트워크를 사용하지 않습니다.

## 성능 측정

2026-11-18, macOS 27.2.1, Release 빌드, 임시 서명 기준입니다. `footprint`, `ps`, `top`으로 측정했으며 Instruments 측정은 아닙니다.

| 항목 | 결과 | 목표 |
|---|---|---|
| 메모리, 팝오버를 열기 전 | 18 MB | 25 MB 이하 |
| 메모리, 팝오버를 연 상태 | 32 MB | 35 MB 이하 |
| 메모리, 팝오버를 닫은 뒤 | 26~33 MB | 35 MB 이하 |
| 메모리 최고값 | 91~94 MB (팝오버를 열 때 잠깐) | 별도 목표 없음 |
| CPU, 대기 상태 10분 평균 | 0.0017% | 0.0% |
| CPU, 실행 상태 10분 평균 | 0.0982% | 0.1% 미만 |
| 유휴 깨우기, 대기 상태 10분 | 11회 | 사실상 0 |
| 유휴 깨우기, 실행 상태 10분 | 389회 | 낮음 |
| 앱 크기 | 928 KB | 5 MB 이하 |

대기 상태는 Claude 감지 대상만 바꾼 측정용 빌드로 측정했습니다.
