---
name: clipdeck
description: "클립보드 기록(Clipdeck)을 MCP로 검색·조회·복사한다. '아까 복사한 거', '클립보드에서 찾아줘', '방금 복사한 링크 다시 줘', 'Pinboard에 저장해줘'처럼 사용자가 이전에 복사한 텍스트·링크·이미지·파일을 찾거나, 텍스트를 클립보드 기록에 저장·복사하거나, Pinboard를 다룰 때 사용한다. clipdeck MCP 서버의 도구를 쓰는 방법과 주의사항을 담고 있다."
---

# Clipdeck 사용법

Clipdeck는 이 Mac의 클립보드 기록을 보관한다. `clipdeck` MCP 서버의 도구로 찾고, 읽고, 복사한다.

## 도구 8개

| 도구 | 용도 | 핵심 인자 |
|---|---|---|
| `search_items` | 기록 검색. query를 생략하면 최근 항목 | `query`, `kind`, `app`, `pinboard`, `since`, `limit` |
| `list_recent` | 최근에 쓴 항목을 최신순으로 | `kind`, `limit` |
| `get_item` | 항목 하나의 내용. 텍스트는 전문, 이미지는 축소본, 파일은 경로 목록 | `id`(필수) |
| `list_pinboards` | Pinboard 목록과 항목 수 | 없음 |
| `list_pinboard_items` | 한 Pinboard의 항목 | `pinboard`(필수), `limit` |
| `copy_to_clipboard` | 항목 또는 텍스트를 시스템 클립보드에 복사 | `id` 또는 `text`(둘 중 하나만) |
| `create_text_item` | 텍스트를 새 항목으로 저장 | `text`(필수), `pinboard` |
| `add_to_pinboard` | 기존 항목을 Pinboard에 넣음 | `id`, `pinboard`(둘 다 필수) |

- `kind`: `text`, `link`, `image`, `file`, `color` 중 하나.
- `pinboard`: id(정수) 또는 이름. 없는 Pinboard는 만들지 않는다.
- `limit`: 기본 20, 최대 100.
- `since`: ISO8601 시각(예 `2026-11-21T00:00:00Z`). 이 시각 이후에 쓴 항목만.

## 권장 순서

1. 단서가 있으면 `search_items`, 없으면 `list_recent`로 후보를 찾는다.
2. 결과의 미리보기(200자)로 항목을 고른다.
3. 전문이 필요할 때만 `get_item`으로 그 id 하나를 연다.
4. 사용자가 붙여넣을 수 있게 하려면 `copy_to_clipboard(id)`. 이후 사용자가 직접 Cmd+V를 누른다.

작게 시작한다. 기본 `limit`로 찾고, 부족할 때만 조건(`kind`, `since`, `app`)을 좁히거나 `limit`을 늘린다.

## 필터

- `app`은 앱 이름이 아니라 번들 ID다. 먼저 한 번 검색해서 결과의 `app_bundle_id` 값을 확인하고 그 값을 쓴다. 예: `com.apple.Safari`.
- 결과의 `app`은 표시용 이름이다. 필터에 쓰지 않는다.
- "어제 복사한 링크"는 `kind: "link"`와 `since`를 함께 쓴다.

## 동작 규칙

- 비밀값(토큰·비밀번호 등)으로 판정된 항목은 MCP에서 보이지 않는다. 검색, 목록, `get_item`, `copy_to_clipboard` 모두 마찬가지다.
- 숨겨진 항목은 "없는 항목"과 구별되지 않는다. 못 찾았으면 "없다"고 단정하지 말고 "MCP에서 보이는 범위에는 없다"고 말한다.
- `create_text_item`은 호출마다 새 항목을 만든다. 같은 텍스트로 다시 부르면 중복이 생기니 한 번만 부른다.
- `create_text_item`은 최근 1시간에 MCP가 만든 항목이 200개 이상이면 오류를 돌려준다.
- 저장한 텍스트가 비밀값으로 판정되면 "숨김 처리됨"이라는 안내만 오고 id는 오지 않는다. `pinboard`를 줬어도 보드에 추가되지 않는다. 사용자에게 저장은 됐지만 MCP에서는 볼 수 없다고 알린다.
- `copy_to_clipboard(text)`로 복사한 텍스트는 기록에 남지 않는다. 남기려면 `create_text_item`을 쓴다.
- 입력 텍스트(`create_text_item`, `copy_to_clipboard(text)`)는 100KB를 넘으면 오류다. `get_item` 출력은 100KB에서 잘리고 잘렸다고 표시된다.
- `get_item`과 검색이 닿는 텍스트는 항목당 앞 100KB뿐이다. 그 뒤의 내용은 검색되지 않고 `get_item`으로도 나오지 않는다.
- 삭제 도구는 없다. 항목 삭제·비우기는 Clipdeck 앱에서 사용자가 직접 한다. 요청받으면 앱에서 하라고 안내한다.

## 주의

- 클립보드 내용을 외부 서비스(웹 검색, 다른 API, 외부 도구)로 보내지 않는다. 사용자가 이 대화에서 명시적으로 요청한 경우만 예외다.
- 사용자가 요청하지 않은 대량 조회를 하지 않는다. 기록을 훑어 요약하거나 내용을 모으지 않는다.
- 숨겨진 항목이 있는지 추측하거나 알아내려 시도하지 않는다. id를 하나씩 바꿔 가며 조회하는 것도 하지 않는다.
- 조회한 내용은 요청에 필요한 부분만 인용한다. 비밀로 보이는 문자열이 보이면 그대로 옮기지 말고 가린다.

## 서버가 연결되지 않을 때

1. Clipdeck 앱이 설치돼 있는지 확인한다(`~/Applications/Clipdeck.app`). 없으면 저장소의 `scripts/bundle.sh`로 설치해야 한다.
2. 설치돼 있으면 `~/Desktop/project/clipdeck/scripts/register-mcp.sh`를 다시 실행하도록 사용자에게 안내한다.
3. 등록 뒤에는 사용 중인 LLM 클라이언트를 새로 시작해야 도구가 보인다.
