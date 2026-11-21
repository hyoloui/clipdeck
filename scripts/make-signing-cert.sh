#!/bin/bash
# 로컬 자체 서명 코드 서명 인증서 "Clipdeck Local Signing"을 로그인 키체인에 1회 만든다.
# 재빌드해도 서명 ID가 같아야 손쉬운 사용 권한(TCC)이 풀리지 않는다.
# 키체인 승인 창이 뜨면 사용자가 승인해야 한다. 이미 있으면 아무것도 하지 않는다.
set -euo pipefail

NAME="Clipdeck Local Signing"
KEYCHAIN="$HOME/Library/Keychains/login.keychain-db"

if security find-identity -p codesigning "$KEYCHAIN" | grep -q "$NAME"; then
  echo "이미 있음: $NAME"
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
security add-trusted-cert -r trustRoot -p codeSign -k "$KEYCHAIN" "$WORK/cert.pem"

echo "생성 완료: $NAME"
security find-identity -v -p codesigning "$KEYCHAIN" | grep "$NAME" || true
