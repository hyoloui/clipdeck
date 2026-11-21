import Foundation

/// 복사된 텍스트가 비밀값(API 키·토큰·비밀번호)인지 판정한다. 참이면 MCP 도구에서 숨긴다.
/// 놓치면 LLM에 비밀값이 노출되고, 과하면 일반 텍스트가 LLM에서 사라진다. 둘의 균형을 맞춘다.
public enum SecretDetector {
    /// 복사할 때마다 호출되므로 아주 큰 텍스트는 앞부분만 검사한다.
    /// MCP에 닿는 텍스트(`items.plain_text`)와 같은 범위라 검사하지 않은 부분은 MCP로도 나가지 않는다.
    static let scanLimit = ClipLimits.plainTextBytes

    // 접두사·형식이 뚜렷한 키(한 번에 훑도록 하나로 합침). 줄·위치와 무관하게 어디서든 찾는다.
    // Regex는 불변이라 스레드 간 공유해도 안전하다(Sendable 표시만 없다)
    nonisolated(unsafe) private static let prefixed = try! Regex([
        #"sk-ant-[A-Za-z0-9_-]{20,}"#,
        #"sk-proj-[A-Za-z0-9_-]{20,}"#,
        #"\bsk-[A-Za-z0-9]{32,}"#,
        #"\b(?:sk|rk)_live_[A-Za-z0-9]{16,}"#,
        #"\bgh[pousr]_[A-Za-z0-9]{36,}"#,
        #"\bgithub_pat_[A-Za-z0-9_]{22,}"#,
        #"\bxox[abprs]-[A-Za-z0-9-]{10,}"#,
        #"\b(?:AKIA|ASIA)[0-9A-Z]{16}\b"#,
        #"\bAIza[0-9A-Za-z_-]{35}"#,
        #"\bya29\.[0-9A-Za-z_-]{20,}"#, // Google OAuth 액세스 토큰
        #"(?:^|[^A-Za-z0-9_-])eyJ[A-Za-z0-9_-]{8,16384}\.[A-Za-z0-9_-]{8,16384}\.[A-Za-z0-9_-]{8,16384}"#,
        #"-----BEGIN [A-Z ]*PRIVATE KEY(?: BLOCK)?-----"#,
    ].joined(separator: "|"))

    /// JWT 세 조각 하나의 최대 길이(그룹 클레임이 많은 payload도 덮는다)
    private static let jwtPartMax = 16384

    // 접두사 정규식의 JWT는 앞에 `-`가 붙으면 시작점으로 보지 않는다(`-eyJ` 반복 입력에서 시작점마다 다시 훑는 것을 막으려고).
    // 그래서 `x-eyJ…`, `--eyJ…`는 토큰 단위 보조 검사가 잡는다: 토큰에서 첫 `eyJ` 위치 한 곳만 보며, 토큰당 선형이다.
    nonisolated(unsafe) private static let jwtAtStart = try! Regex(
        "^eyJ[A-Za-z0-9_-]{8,\(jwtPartMax)}\\.[A-Za-z0-9_-]{8,\(jwtPartMax)}\\.[A-Za-z0-9_-]{8,\(jwtPartMax)}")

    private static func hasEmbeddedJWT(_ token: Substring) -> Bool {
        guard let r = token.range(of: "eyJ") else { return false }
        // 앞 16384자 안에서 찾은 위치부터, JWT 세 조각 길이만큼만 본다
        guard token.distance(from: token.startIndex, to: r.lowerBound) <= jwtPartMax else { return false }
        let tail = token[r.lowerBound...].prefix(3 * jwtPartMax + 8)
        return tail.prefixMatch(of: jwtAtStart) != nil
    }

    // 키-값 형태. 값은 따옴표를 뺀 본문(3번째 캡처)만 판정에 쓴다.
    nonisolated(unsafe) private static let keyValue = try! Regex(
        #"(?i)(?:password|passwd|secret|token|api[_-]?key)[A-Za-z0-9_-]{0,32}["']?[ \t]*([:=])[ \t]*(["']?)([^\s"']{6,})"#)

    nonisolated(unsafe) private static let uuid = try! Regex(
        #"[0-9A-Fa-f]{8}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{12}"#)

    public static func isSecret(_ text: String) -> Bool {
        if text.isEmpty { return false }
        let scanned = ClipLimits.prefix(text, maxBytes: scanLimit)

        if scanned.firstMatch(of: prefixed) != nil { return true }
        for m in scanned.matches(of: keyValue) where isRealSecretValue(m) { return true }
        return scanned.split(whereSeparator: \.isWhitespace).contains { hasEmbeddedJWT($0) || isHighEntropy($0) }
    }

    /// `token: String`, `API_KEY=${API_KEY}`처럼 값이 아니라 타입·참조인 경우를 거른다
    private static func isRealSecretValue(_ m: Regex<AnyRegexOutput>.Match) -> Bool {
        guard let sep = m.output[1].substring, let quote = m.output[2].substring,
              let value = m.output[3].substring else { return false }
        if let first = value.first, "$<{%([".contains(first) { return false }
        // 따옴표 없는 `:` 뒤 값이 타입 이름이면 선언이다(`token: String`, `password: String?`).
        // 영문자만이라는 이유로 통째로 빼면 `password: correcthorsebattery`를 놓치므로 타입 이름만 거른다.
        if sep == ":" && quote.isEmpty && isTypeName(value) { return false }
        return true
    }

    private static let typeKeywords: Set<String> = [
        "string", "number", "boolean", "any", "str", "bytes", "null", "nil", "none",
        "undefined", "true", "false",
    ]

    nonisolated(unsafe) private static let sizedNumeric = try! Regex(#"(?:U?Int|Float)(?:8|16|32|64)"#)
    nonisolated(unsafe) private static let genericType = try! Regex(#"[A-Z][A-Za-z]*<([A-Za-z0-9_, ?\[\]<>.]*)>"#)

    /// 뒤의 `; , ? !`를 뗀 값이 타입 이름인가: 대문자로 시작하는 영문자만(String, Data, Token),
    /// `Int64`·`UInt8`·`Float32` 꼴, `Optional<String>` 꼴, 또는 소문자 타입 키워드.
    /// 숫자가 섞인 `Summer2024`·`P4ssw0rd`·`Welcome1` 같은 비밀번호는 타입 이름이 아니다.
    private static func isTypeName(_ value: Substring) -> Bool {
        let v = String(value.reversed().drop { ";,?!".contains($0) }.reversed())
        guard let first = v.first else { return false }
        if typeKeywords.contains(v) { return true }
        if v.wholeMatch(of: sizedNumeric) != nil { return true }
        // `Optional<String>`은 타입, `Secret<abc123xyz>`처럼 안쪽에 숫자 섞인 소문자 시작 토큰이 있으면 값이다
        if let m = v.wholeMatch(of: genericType), let inner = m.output[1].substring {
            let parts = inner.split { !($0.isLetter || $0.isNumber || $0 == "_") }
            return !parts.contains { $0.first?.isLowercase == true && $0.contains(where: \.isNumber) }
        }
        return first.isUppercase && v.allSatisfy { $0.isASCII && $0.isLetter }
    }

    /// 고엔트로피 판정(공백으로 나눈 토큰 단위).
    /// 조건: 앞뒤 따옴표·괄호를 뗀 토큰이 24자 이상, 문자가 `[A-Za-z0-9_+=/-]`뿐, 대·소문자·숫자 모두 포함,
    /// 순수 hex(git SHA·sha256)·UUID 아님, 엔트로피 4.0 bit/문자 이상, 단어 조각 비율 50% 이하.
    /// - 문자 집합 제한: `\ . : ?`가 들어가면 경로·도메인·URL이다(`/`는 표준 base64 키에 쓰여 허용하고, 점 없는 경로는
    ///   단어 조각 비율로 거른다). 검토에서 `/Users/.../SecretDetector.swift`,
    ///   `Sources/.../SecretDetector.swift:42`, `docs/ADR-0003-...md`, `C:\Users\...docx`,
    ///   `www.youtube.com/watch?v=...`, `com.example.clipdeck.MainActivity2Kt`가 엔트로피 4.0만으로 잡혔다.
    /// - 단어 조각 비율: 엔트로피 4.0은 24자 이상이면 알파벳이 거의 반복되지 않는 식별자도 넘는다
    ///   (`fetchUserProfileWithAuth2Token`, `handleUserAuthenticationCallback2`, `NSKeyedUnarchiverDelegate`,
    ///   `feature-add-clipboard-history-v2-final`이 실제로 4.0을 넘었다). 그래서 `[A-Z]?[a-z]{3,}`(영단어 조각)이
    ///   토큰 길이의 절반을 넘으면 식별자로 보고 뺀다. 무작위 키(`aZ3kQ9pL...`, base64url 40자)는 소문자가
    ///   1~2자씩 끊겨 조각 비율이 0에 가깝다. 엔트로피 4.0 자체는 조정하지 않았다.
    nonisolated(unsafe) private static let wordPiece = try! Regex(#"[A-Z]?[a-z]{3,}"#)

    private static func isHighEntropy(_ raw: Substring) -> Bool {
        // 문장 끝 구두점(`키는 ....`, `Bearer ....`)과 따옴표·괄호를 양쪽에서 뗀다
        let token = raw.trimmingCharacters(in: CharacterSet(charactersIn: "\"'`,;()[]{}<>.:?!"))
        guard token.count >= 24, !token.contains("://") else { return false }
        var hasUpper = false, hasLower = false, hasDigit = false, allHex = true
        for ch in token.unicodeScalars {
            switch ch.value {
            case 0x41...0x5A: hasUpper = true
            case 0x61...0x7A: hasLower = true
            case 0x30...0x39: hasDigit = true
            case 0x5F, 0x2B, 0x3D, 0x2D, 0x2F: break // _ + = - /
            default: return false
            }
            if !ch.properties.isASCIIHexDigit { allHex = false }
        }
        guard hasUpper, hasLower, hasDigit, !allHex else { return false }
        if token.wholeMatch(of: uuid) != nil { return false }
        let wordChars = token.matches(of: wordPiece).reduce(0) { $0 + token[$1.range].count }
        if Double(wordChars) / Double(token.count) > 0.5 { return false }
        return shannonEntropy(token) >= 4.0
    }

    private static func shannonEntropy(_ s: String) -> Double {
        var counts: [Character: Int] = [:]
        for ch in s { counts[ch, default: 0] += 1 }
        let n = Double(s.count)
        return counts.values.reduce(0) { acc, c in
            let p = Double(c) / n
            return acc - p * log2(p)
        }
    }
}
