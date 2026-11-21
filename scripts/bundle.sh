#!/bin/bash
# 빌드 → ~/Applications/Clipdeck.app 조립 → 서명 → 재실행
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
APP="$HOME/Applications/Clipdeck.app"
SIGN_NAME="Clipdeck Local Signing"

swift build -c release
BIN="$(swift build -c release --show-bin-path)"

# 실행 중인 Clipdeck만 종료(다른 앱은 건드리지 않는다)
pkill -x Clipdeck || true
for _ in 1 2 3 4 5 6 7 8 9 10; do pgrep -x Clipdeck >/dev/null || break; sleep 0.3; done

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN/Clipdeck" "$BIN/clipdeck-mcp" "$APP/Contents/MacOS/"
cp Resources/Info.plist "$APP/Contents/Info.plist"
cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"

if security find-identity -p codesigning | grep -q "$SIGN_NAME"; then
  IDENTITY="$SIGN_NAME"
else
  echo "경고: '$SIGN_NAME' 인증서가 없어 임시 서명(ad-hoc)을 씁니다. 재빌드마다 서명이 바뀌어 손쉬운 사용 권한이 풀립니다." >&2
  echo "      scripts/make-signing-cert.sh 를 먼저 실행하세요." >&2
  IDENTITY="-"
fi
codesign --force --options runtime --sign "$IDENTITY" "$APP/Contents/MacOS/clipdeck-mcp"
codesign --force --options runtime --sign "$IDENTITY" "$APP"

open "$APP"
echo "설치 완료: $APP"
