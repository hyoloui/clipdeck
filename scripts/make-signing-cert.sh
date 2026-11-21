#!/bin/bash
# 로컬 자체 서명 코드 서명 인증서 "Clipdeck Local Signing"을 로그인 키체인에 1회 만든다.
# 재빌드해도 서명 ID가 같아야 손쉬운 사용 권한(TCC)이 풀리지 않는다.
# 키체인 승인 창이 뜨면 사용자가 승인해야 한다. 이미 있으면 아무것도 하지 않는다.
set -euo pipefail

NAME="Clipdeck Local Signing"
KEYCHAIN="$HOME/Library/Keychains/login.keychain-db"

# 신뢰까지 끝난(유효한) identity만 본다. 출력은 변수에 담아 grep(pipefail·SIGPIPE 방지)
valid_identities() { security find-identity -v -p codesigning "$KEYCHAIN" || true; }
all_identities() { security find-identity -p codesigning "$KEYCHAIN" || true; }

if [[ "$(valid_identities)" == *"$NAME"* ]]; then
  echo "이미 있음(유효): $NAME"
  exit 0
fi

fail_trust() {
  echo "오류: '$NAME' 인증서는 있으나 코드 서명용으로 신뢰되지 않습니다." >&2
  echo "      키체인 승인 창이 취소됐거나 실패했을 수 있습니다. 터미널에서 직접 실행하세요:" >&2
  echo "      security find-certificate -c '$NAME' -p '$KEYCHAIN' > /tmp/clipdeck-cert.pem && security add-trusted-cert -r trustRoot -p codeSign -k '$KEYCHAIN' /tmp/clipdeck-cert.pem" >&2
  exit 1
}

# 인증서는 있는데 유효하지 않으면 신뢰 설정만 다시 시도한다
if [[ "$(all_identities)" == *"$NAME"* ]]; then
  PEM="$(mktemp)"
  security find-certificate -c "$NAME" -p "$KEYCHAIN" > "$PEM"
  security add-trusted-cert -r trustRoot -p codeSign -k "$KEYCHAIN" "$PEM" || { rm -f "$PEM"; fail_trust; }
  rm -f "$PEM"
  [[ "$(valid_identities)" == *"$NAME"* ]] || fail_trust
  echo "신뢰 설정 완료: $NAME"
  exit 0
fi

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
PASS="$(uuidgen)"

cat > "$WORK/openssl.cnf" <<CNF
[req]
distinguished_name = dn
x509_extensions = ext
prompt = no
[dn]
CN = $NAME
[ext]
basicConstraints = critical,CA:false
keyUsage = critical,digitalSignature
extendedKeyUsage = critical,codeSigning
CNF

# /usr/bin/openssl(LibreSSL)을 써야 security import가 읽는 p12가 나온다
/usr/bin/openssl req -x509 -newkey rsa:2048 -nodes -days 3650 \
  -config "$WORK/openssl.cnf" -keyout "$WORK/key.pem" -out "$WORK/cert.pem"
/usr/bin/openssl pkcs12 -export -inkey "$WORK/key.pem" -in "$WORK/cert.pem" \
  -name "$NAME" -passout "pass:$PASS" -out "$WORK/cert.p12"

# 개인 키는 codesign만 승인 창 없이 쓰게 허용
security import "$WORK/cert.p12" -k "$KEYCHAIN" -P "$PASS" -T /usr/bin/codesign
# 코드 서명용으로 신뢰(사용자 승인 창이 뜬다)
security add-trusted-cert -r trustRoot -p codeSign -k "$KEYCHAIN" "$WORK/cert.pem" || fail_trust
[[ "$(valid_identities)" == *"$NAME"* ]] || fail_trust

echo "생성 완료: $NAME"
