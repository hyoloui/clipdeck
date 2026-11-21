#!/bin/bash
# Clipdeck MCP 서버를 skillshare로 Claude·Codex·Antigravity에 한 번에 등록한다.
# 사용: scripts/register-mcp.sh [--dry-run]
set -euo pipefail

MCP_BIN="$HOME/Applications/Clipdeck.app/Contents/MacOS/clipdeck-mcp"
NAME="clipdeck"
DRY=0
case "${1:-}" in
  "") ;;
  --dry-run) DRY=1 ;;
  *) echo "사용법: $0 [--dry-run]" >&2; exit 2 ;;
esac

# 단계 실행: 출력은 그대로 보여 주고, 실패하면 단계 이름과 함께 종료한다.
step() {
  local title="$1"; shift
  echo "==> $title"
  echo "    \$ $*"
  if ! "$@"; then
    echo "실패: '$title' 단계에서 멈췄습니다." >&2
    exit 1
  fi
}

# 1) 실행 파일 확인
if [[ ! -x "$MCP_BIN" ]]; then
  echo "clipdeck-mcp를 실행할 수 없습니다: $MCP_BIN" >&2
  echo "먼저 scripts/bundle.sh를 실행하세요." >&2
  exit 1
fi

# 2) 동작 확인: 임시 데이터 폴더로 initialize 한 줄을 보낸다
DATA_DIR="$(mktemp -d)"
trap 'rm -rf "$DATA_DIR"' EXIT
INIT='{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2024-11-05","capabilities":{},"clientInfo":{"name":"register-mcp","version":"1"}}}'
echo "==> clipdeck-mcp 동작 확인 (임시 데이터 폴더)"
if ! REPLY="$(printf '%s\n' "$INIT" | CLIPDECK_DATA_DIR="$DATA_DIR" "$MCP_BIN" 2>"$DATA_DIR/stderr")"; then
  REPLY=""
fi
if [[ "$REPLY" != *'"name":"clipdeck"'* ]]; then
  echo "clipdeck-mcp가 initialize에 올바르게 응답하지 않았습니다." >&2
  echo "응답: ${REPLY:-(없음)}" >&2
  [[ -s "$DATA_DIR/stderr" ]] && { echo "stderr:" >&2; cat "$DATA_DIR/stderr" >&2; }
  echo "오래된 빌드일 수 있습니다. scripts/bundle.sh를 다시 실행한 뒤 시도하세요." >&2
  exit 1
fi
echo "    정상 응답 확인"

# 3) 등록(이미 있으면 같은 값으로 갱신)
FLAGS=()
[[ $DRY -eq 1 ]] && FLAGS=(--dry-run)
if skillshare mcp list --no-tui 2>/dev/null | grep -Eq "^[[:space:]]*$NAME[[:space:]]"; then
  ACTION=edit
else
  ACTION=add
fi
step "MCP 등록 ($ACTION)" skillshare mcp "$ACTION" "$NAME" --no-tui ${FLAGS[@]+"${FLAGS[@]}"} \
  --target claude --target codex --target antigravity -- "$MCP_BIN"

# 4) 클라이언트 설정에 반영
step "MCP 동기화" skillshare sync mcp --no-tui ${FLAGS[@]+"${FLAGS[@]}"}

# 5) 실제 호출까지 확인
if [[ $DRY -eq 1 ]]; then
  echo "==> (dry-run) 마지막 단계는 실행하지 않습니다: skillshare mcp check $NAME --live"
  echo "dry-run 완료: 아무것도 바꾸지 않았습니다."
else
  step "등록 확인" skillshare mcp check "$NAME" --live
  echo "완료: claude·codex·antigravity 세 대상이 모두 정상인지 위 출력을 확인하세요."
fi
