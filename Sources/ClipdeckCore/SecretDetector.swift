import Foundation

/// 복사된 텍스트가 비밀값(API 키·토큰·비밀번호)인지 판정한다. 참이면 MCP 도구에서 숨긴다.
/// 놓치면 LLM에 비밀값이 노출되고, 과하면 일반 텍스트가 LLM에서 사라진다. 둘의 균형을 맞춘다.
public enum SecretDetector {
    /// 복사할 때마다 호출되므로 아주 큰 텍스트는 앞부분만 검사한다
    static let scanLimit = 64 * 1024

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
        #"\beyJ[A-Za-z0-9_-]{8,}\.[A-Za-z0-9_-]{8,}\.[A-Za-z0-9_-]{8,}"#,
        #"-----BEGIN [A-Z ]*PRIVATE KEY-----"#,
    ].joined(separator: "|"))

    // 키-값 형태. 값은 따옴표를 뺀 본문(3번째 캡처)만 판정에 쓴다.
    nonisolated(unsafe) private static let keyValue = try! Regex(
        #"(?i)(?:password|passwd|secret|token|api[_-]?key)(?:[_-]?(?:key|token))?["']?\s*([:=])\s*(["']?)([^\s"']{6,})"#)

    nonisolated(unsafe) private static let uuid = try! Regex(
        #"[0-9A-Fa-f]{8}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{12}"#)

    public static func isSecret(_ text: String) -> Bool {
        if text.isEmpty { return false }
        let scanned = text.utf8.count > scanLimit
            ? String(decoding: text.utf8.prefix(scanLimit), as: UTF8.self) : text

        if scanned.firstMatch(of: prefixed) != nil { return true }
        for m in scanned.matches(of: keyValue) where isRealSecretValue(m) { return true }
        return scanned.split(whereSeparator: \.isWhitespace).contains { isHighEntropy($0) }
    }

    /// `token: String`, `API_KEY=${API_KEY}`처럼 값이 아니라 타입·참조인 경우를 거른다
    private static func isRealSecretValue(_ m: Regex<AnyRegexOutput>.Match) -> Bool {
        guard let sep = m.output[1].substring, let quote = m.output[2].substring,
              let value = m.output[3].substring else { return false }
        if let first = value.first, "$<{%(".contains(first) { return false }
        // 따옴표 없는 `: 영문자만`은 타입 선언(token: String)이나 설명문일 가능성이 높다
        if sep == ":" && quote.isEmpty && value.allSatisfy(\.isLetter) { return false }
        return true
    }

    /// 고엔트로피 판정(공백으로 나눈 토큰 단위).
    /// 기준: 24자 이상, 대·소문자·숫자 모두 포함, 샤넌 엔트로피 4.0 bit/문자 이상,
    /// URL·순수 hex(git SHA·sha256)·UUID 제외.
    /// 4.0은 지시서 값 그대로이며 조정하지 않았다. 24자 토큰의 이론 최대가 약 4.58이라
    /// 4.0이면 문자가 거의 반복되지 않는 무작위 문자열만 통과한다. 반면 camelCase 식별자
    /// (`UserProfileViewControllerFactory2` 약 3.6)와 kebab 브랜치명은 반복 문자 때문에
    /// 걸리지 않는다(테스트로 확인).
    private static func isHighEntropy(_ raw: Substring) -> Bool {
        let token = raw.trimmingCharacters(in: CharacterSet(charactersIn: "\"'`,;()[]{}<>"))
        guard token.count >= 24, !token.contains("://") else { return false }
        var hasUpper = false, hasLower = false, hasDigit = false, allHex = true
        for ch in token.unicodeScalars {
            switch ch.value {
            case 0x41...0x5A: hasUpper = true
            case 0x61...0x7A: hasLower = true
            case 0x30...0x39: hasDigit = true
            default: break
            }
            if !ch.properties.isASCIIHexDigit { allHex = false }
        }
        guard hasUpper, hasLower, hasDigit, !allHex else { return false }
        if token.wholeMatch(of: uuid) != nil { return false }
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
