# Clipdeck

**맥에서 복사한 것을 `⇧⌘V` 한 번으로 다시 꺼내는 클립보드 관리자.**
같은 기록을 LLM 도구가 MCP로 검색하고, API 키와 비밀번호는 LLM에게 보이지 않습니다.

![macOS 14+](https://img.shields.io/badge/macOS-14%2B-black) ![Swift 6](https://img.shields.io/badge/Swift-6-orange) ![License: MIT](https://img.shields.io/badge/License-MIT-blue)

```
┌────────────────────────────────────────────────────────────┐
│  검색…                              [종류▾] [앱▾] [기간▾]  │
│  기록 · 업무 · 코드 조각 · +                                │
├──────────────────────────────┬─────────────────────────────┤
│ ▸ 1  npm run dev             │                             │
│   2  https://example.com/…   │   선택한 항목 미리보기       │
│   3  [숨김] sk-a••••         │   출처 앱 · 시각 · 크기      │
│   4  이미지 1280×720         │                             │
├──────────────────────────────┴─────────────────────────────┤
│  ↩ 붙여넣기   ⇧↩ 일반 텍스트   ⌘1-9 바로   ⌘P 고정   esc    │
└────────────────────────────────────────────────────────────┘
```

## 왜 Clipdeck인가

방금 복사한 명령어를 다른 것으로 덮어썼을 때, 다시 찾으러 돌아가지 않아도 됩니다. 텍스트, 링크, 이미지, 파일, 색을 모두 기록하고 쓰던 앱에 바로 붙여 줍니다.

- 손이 키보드를 떠나지 않습니다. 패널을 열고, 몇 글자 치고, `↩`를 누르면 끝납니다.
- 자주 쓰는 문구는 Pinboard에 고정합니다. 기록은 한 달 뒤 지워져도 고정한 항목은 남습니다.
- LLM에게 "아까 복사한 그 URL 찾아줘"라고 말할 수 있습니다. MCP 서버가 함께 들어 있습니다.
- 데이터는 이 맥 밖으로 나가지 않습니다. 계정도 동기화도 없습니다.
- 가볍습니다. 대기 중 메모리 33MB, CPU 0.1%로 측정됐습니다(Apple Silicon 맥 한 대 기준).

## 비밀값은 LLM에게 보이지 않습니다

API 키, 토큰, 비밀번호처럼 보이는 텍스트는 복사하는 순간 자물쇠가 붙습니다. 패널에서는 평소처럼 붙여넣을 수 있고, MCP 쪽에서는 검색에도 목록에도 나오지 않습니다. LLM 쪽에서는 숨겨진 항목이 없는 항목과 똑같이 보입니다.

비밀번호 관리자처럼 통째로 숨기고 싶은 앱은 설정에서 지정합니다. 잘못 숨겨진 항목은 `⌘H`로 풉니다.

## 설치

macOS 14 이상과 Swift 6 툴체인이 필요합니다. Xcode 없이 Command Line Tools만으로 빌드됩니다.

```sh
git clone https://github.com/hyoloui/clipdeck.git && cd clipdeck
scripts/make-signing-cert.sh   # 처음 한 번. 로컬 서명 인증서를 만듭니다
scripts/bundle.sh              # 빌드해서 ~/Applications/Clipdeck.app 으로 설치하고 실행합니다
```

처음 붙여넣을 때 손쉬운 사용 권한을 묻습니다. 시스템 설정 > 개인정보 보호 및 보안 > 손쉬운 사용에서 Clipdeck을 켜 주세요.

## 단축키

| 키 | 동작 |
|---|---|
| `⇧⌘V` | 패널 열기 (설정에서 바꿀 수 있습니다) |
| `↩` / `⇧↩` | 붙여넣기 / 서식 없이 붙여넣기 |
| `⌘1`~`⌘9` | 그 순번 항목을 바로 붙여넣기 |
| `Tab` / `⇧Tab` | 다음 보드 / 이전 보드 |
| `⌘P` | Pinboard에 고정 |
| `⌘H` / `⌘R` | LLM에게 숨기기 전환 / 가려진 내용 보기 |
| `⌘,` | 설정 |

패널은 빈 곳을 끌어 옮길 수 있고, 옮긴 자리를 기억합니다.

## LLM 도구에 연결하기

`clipdeck-mcp`는 표준 입출력으로 동작하는 MCP 서버입니다. MCP를 지원하는 도구라면 무엇이든 연결할 수 있습니다. 쓰는 도구의 MCP 설정에 실행 파일 경로를 등록하고 도구를 다시 시작하세요.

```json
{
  "mcpServers": {
    "clipdeck": { "command": "/Users/<사용자>/Applications/Clipdeck.app/Contents/MacOS/clipdeck-mcp" }
  }
}
```

연결되면 LLM이 기록을 검색하고, 항목 전문을 읽고, 클립보드에 복사하고, Pinboard에 저장할 수 있습니다. 삭제 도구는 없습니다.

LLM이 도구를 더 잘 쓰게 하려면 [`skill/clipdeck/SKILL.md`](skill/clipdeck/SKILL.md)를 쓰는 도구의 스킬 위치에 넣거나, 내용을 지침에 붙여 넣으세요. 넣지 않아도 도구는 동작합니다.

<details>
<summary>여러 도구의 MCP 설정을 한곳에서 관리한다면</summary>

`scripts/register-mcp.sh`는 [skillshare](https://github.com/runkids/skillshare)로 등록하는 예시 스크립트입니다. `--dry-run`을 붙이면 실행할 명령만 보여 줍니다.

</details>

## 더 알아보기

- 데이터는 `~/Library/Application Support/Clipdeck`에 SQLite로 저장됩니다. `CLIPDECK_DATA_DIR` 환경 변수로 위치를 바꿀 수 있습니다.
- 외부 패키지를 쓰지 않습니다. `swift test`로 테스트 198개를 돌립니다.
- 설계 배경은 [`docs/spec.md`](docs/spec.md)에, 직접 확인한 항목은 [`docs/verification.md`](docs/verification.md)에 있습니다.

## 라이선스

[MIT](LICENSE)
