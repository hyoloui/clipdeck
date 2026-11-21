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

# 2) 동작 확인: 임시 데이터 폴더로 initialize 한 줄을 보낸다(5초 제한)
DATA_DIR="$(mktemp -d)"
trap 'rm -rf "$DATA_DIR"' EXIT
INIT='{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2024-11-05","capabilities":{},"clientInfo":{"name":"register-mcp","version":"1"}}}'
echo "==> clipdeck-mcp 동작 확인 (임시 데이터 폴더)"
# 종료 코드는 무시하고 응답 내용만 본다. 시간 초과(SIGALRM)는 응답이 비어 있어 아래에서 걸린다.
INIT_REPLY="$(printf '%s\n' "$INIT" | CLIPDECK_DATA_DIR="$DATA_DIR" perl -e 'alarm 5; exec @ARGV' "$MCP_BIN" 2>"$DATA_DIR/stderr" || true)"
if [[ "$INIT_REPLY" != *'"name":"clipdeck"'* ]]; then
  echo "MCP 실행 파일이 응답하지 않습니다(오래된 빌드일 수 있음). scripts/bundle.sh를 다시 실행하세요." >&2
  echo "응답: ${INIT_REPLY:-(없음)}" >&2
  [[ -s "$DATA_DIR/stderr" ]] && { echo "stderr:" >&2; cat "$DATA_DIR/stderr" >&2; }
  exit 1
fi
echo "    정상 응답 확인"

# 3) 등록. --replace는 없으면 새로 만들고 있으면 같은 값으로 덮어쓴다(등록 여부를 따로 판별하지 않는다).
FLAGS=()
[[ $DRY -eq 1 ]] && FLAGS=(--dry-run)
step "MCP 등록" skillshare mcp add "$NAME" --replace --no-tui ${FLAGS[@]+"${FLAGS[@]}"} \
  --target claude --target codex --target antigravity -- "$MCP_BIN"

# 4) 클라이언트 설정에 반영
step "MCP 동기화" skillshare sync mcp --no-tui ${FLAGS[@]+"${FLAGS[@]}"}

# 5) 실제 호출까지 확인. 종료 코드가 문서화돼 있지 않아 JSON 출력에서 세 대상을 직접 확인한다.
if [[ $DRY -eq 1 ]]; then
  echo "==> (dry-run) 마지막 단계는 실행하지 않습니다: skillshare mcp check $NAME --live --json"
  echo "dry-run 완료: 아무것도 바꾸지 않았습니다."
  exit 0
fi
echo "==> 등록 확인"
echo "    \$ skillshare mcp check $NAME --live --json"
CHECK_RC=0
CHECK_OUT="$(skillshare mcp check "$NAME" --live --json)" || CHECK_RC=$?
echo "$CHECK_OUT"
BAD=()
[[ $CHECK_RC -eq 0 ]] || BAD+=("종료 코드 $CHECK_RC")
[[ "$CHECK_OUT" == *'"errors": 0'* ]] || BAD+=("errors가 0이 아님")
for t in claude codex antigravity; do
  [[ "$CHECK_OUT" == *"\"target\": \"$t\""* ]] || BAD+=("$t 대상 상태 없음")
done
if [[ ${#BAD[@]} -gt 0 ]]; then
  echo "실패: '등록 확인' 단계: ${BAD[*]}" >&2
  exit 1
fi
echo "완료: claude·codex·antigravity 세 대상이 모두 확인됐습니다."
