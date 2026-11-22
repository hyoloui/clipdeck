# Clipdeck

macOS용 로컬 클립보드 관리자. 복사한 텍스트·링크·이미지·파일·색을 기록하고, 단축키로 여는 패널에서 검색해 붙여넣는다. 같은 기록을 MCP 서버(`clipdeck-mcp`)로 열어, MCP를 지원하는 LLM 클라이언트가 검색·조회·복사할 수 있다. 데이터는 이 Mac 안에만 있고, 비밀값으로 판정된 항목은 MCP에서 숨긴다. 설계는 `docs/spec.md`에 있다.

## 요구 사항

- macOS 14 이상, Swift 6 툴체인(Command Line Tools로 충분). 외부 패키지 없음.

## 빌드·설치

```sh
scripts/make-signing-cert.sh   # 1회. 로컬 서명 인증서를 만든다(키체인 승인 창이 뜰 수 있음)
scripts/bundle.sh              # 빌드 → ~/Applications/Clipdeck.app 조립·서명 → 실행
```

인증서를 먼저 만들어 두면 재빌드해도 서명이 같아서 권한이 풀리지 않는다. 코드를 바꾼 뒤에는 `scripts/bundle.sh`만 다시 실행한다.

## 패널 키

| 키 | 동작 |
|---|---|
| ⇧⌘V | 패널 열기(설정에서 변경) |
| ↑↓ · ↩ · ⇧↩ | 이동 · 붙여넣기 · 일반 텍스트로 붙여넣기 |
| ⌘1–9 | 해당 순번 바로 붙여넣기 |
| Tab · ⇧Tab | 다음 · 이전 보드 |
| ⌘P · ⌘C · ⌫ | 보드에 고정 · 복사만 · 삭제(보드 탭에서는 보드에서 빼기) |
| ⌘H · ⌘R | MCP 숨김 전환 · 가려진 내용 보기 |
| ⌘, · Esc(⌘W) | 설정 · 닫기 |

## 권한

붙여넣기(키 입력 전송)에 **손쉬운 사용** 권한이 필요하다. 시스템 설정 > 개인정보 보호 및 보안 > 손쉬운 사용에서 Clipdeck를 켠다.

## MCP 등록

`clipdeck-mcp`는 표준 입출력(stdio)으로 동작하는 MCP 서버다. MCP를 지원하는 클라이언트라면 어느 것이든 쓸 수 있다. 쓰는 클라이언트의 MCP 설정에 아래 실행 파일을 인자 없이 등록한다.

```
~/Applications/Clipdeck.app/Contents/MacOS/clipdeck-mcp
```

설정 파일이 JSON 형식인 클라이언트라면 보통 이런 모양이다. 경로는 절대 경로로 적는다.

```json
{
  "mcpServers": {
    "clipdeck": { "command": "/Users/<사용자>/Applications/Clipdeck.app/Contents/MacOS/clipdeck-mcp" }
  }
}
```

등록한 뒤 클라이언트를 다시 시작한다. 앱을 다시 설치했을 때도 클라이언트를 다시 시작해야 새 실행 파일이 쓰인다.

여러 클라이언트의 MCP 설정을 한곳에서 관리하는 도구를 쓴다면 그 도구로 등록해도 된다. `scripts/register-mcp.sh`는 그런 도구 가운데 하나인 [skillshare](https://github.com/runkids/skillshare)를 쓰는 사람을 위한 예시 스크립트다. 꼭 쓸 필요는 없다.

## 사용법 스킬 설치 (선택)

`skill/clipdeck/SKILL.md`는 LLM이 이 도구를 올바르게 쓰도록 안내하는 문서다. 도구 8개의 용도, 권장 순서, 주의사항이 들어 있다. MCP 등록만으로도 도구는 동작하며, 스킬은 더 잘 쓰게 하는 보조 자료다.

쓰는 LLM 클라이언트가 스킬(에이전트용 지시 문서)을 지원하면 `skill/clipdeck` 폴더를 그 클라이언트의 스킬 위치에 넣는다. 스킬 기능이 없는 클라이언트라면 `SKILL.md`의 내용을 시스템 프롬프트나 프로젝트 지침에 붙여 넣어도 된다.

## 데이터 위치

- 기본: `~/Library/Application Support/Clipdeck` (SQLite 데이터베이스와 큰 표현 데이터 `blobs/`)
- `CLIPDECK_DATA_DIR` 환경 변수로 바꿀 수 있다. 실험할 때는 임시 폴더를 지정한다.

## 테스트

```sh
swift test
```

샌드박스 안에서는 `swift test --disable-sandbox`를 쓴다.

## 라이선스

MIT. [LICENSE](LICENSE) 참고.
