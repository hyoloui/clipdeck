import Foundation
import Testing
@testable import ClipdeckCore

// 가짜 키: 실제 형식·길이만 맞춘 고정 무작위 문자열. 접두사와 본문을 나눠 이어 붙여
// 소스에 진짜처럼 보이는 리터럴이 남지 않게 한다(저장소 비밀값 검사 회피).
private let body40 = "q7Lm2Xv9Rt4Kp8Zw3Hd6Ns1Bc5Yf0Ge2Ja9Uo7E"          // 40자
private let body36 = "Rt4Kp8Zw3Hd6Ns1Bc5Yf0Ge2Ja9Uo7Eq7Lm"             // 36자
private let body82 = String(repeating: "aB3dE6gH9jK2mN5pQ8sT1vW4yZ7", count: 4).prefix(82)

private let detectCases: [(name: String, text: String)] = [
    ("anthropic", "sk-ant-" + "api03-" + body40),
    ("openai-proj", "sk-" + "proj-" + body40),
    ("github-classic", "gh" + "p_" + body36),
    ("github-fine", "github_" + "pat_" + body82),
    ("slack", "xox" + "b-1234-5678-abcd"),
    ("aws", "AK" + "IA" + "Q7LM2XV9RT4KP8ZW"),
    ("google", "AI" + "za" + "Sy" + "Rt4Kp8Zw3Hd6Ns1Bc5Yf0Ge2Ja9Uo7Eq7L"),
    ("jwt", "ey" + "JhbGciOiJIUzI1NiJ9." + "ey" + "JzdWIiOiIxMjM0NTY3ODkwIn0." + "dBjftJeZ4CVPmB92K27uhbUJU1p1r"),
    ("private-key", "ssh key:\n-----BEGIN " + "OPENSSH PRIVATE KEY-----\nb3BlbnNzaC1rZXktdjE\n-----END OPENSSH PRIVATE KEY-----"),
    ("kv-env", "DB_PASSWORD=hunter2hunter2"),
    ("kv-quoted", "api_key: \"Zx9fQ2mL\""),
    ("yaml-password", "password: correcthorsebattery"),
    ("yaml-postgres", "POSTGRES_PASSWORD: postgres"),
    ("pgp-key", "-----BEGIN PGP " + "PRIVATE KEY BLOCK-----\nlQdGBF"),
    ("base64url-40", "Zx9Qm2Lr7Tn4Vb8Kp1Hs6" + "Wd3Yc5Jf0Ga2Ne9Ru4Mt7"),
    ("pw-summer", "password: Summer2024"),
    ("pw-summer-bang", "password: Summer2024!"),
    ("pw-leet", "password: P4ssw0rd"),
    ("pw-welcome", "password: Welcome1"),
    ("pw-db", "DB_PASSWORD: Tr0ub4dor3"),
    ("secret-mixed", "secret: Xk3pQ9rT2mL8"),
    ("sentence-period", "키는 aZ3kQ9pL2mX7vB1nC8dF4gH6jK0sT5wY."),
    ("bearer-period", "Bearer aZ3kQ9pL2mX7vB1nC8dF4gH6jK0sT5wY."),
    ("base64-slash", "Qm7/Xz2+Lr9Tn4Vb8" + "Kp1Hs6Wd3/Yc5Jf0+Ga2Nq7"),
    ("aws-secret", "aws_secret_access_key = Qm7/Xz2+Lr9Tn4Vb8" + "Kp1Hs6Wd3/Yc5Jf0+Ga2Nq7"),
    ("aws-short", "aws_secret_access_key = abcdefgh12345678"),
    ("kv-suffix", "client_secret_key: abcdefgh1234"),
    ("kv-v2", "auth_token_v2=abcdefgh1234"),
    ("secret-generic", "token: Secret<abc123xyz>"),
    ("kv-json", "{\"access_token\": \"abc123def456\"}"),
    ("high-entropy", "aZ3kQ9pL2mX7vB1nC8dF4gH6jK0sT5wY"),
    ("embedded-in-doc", "회의록\n내용 정리\n배포 키는 " + "gh" + "p_" + body36 + " 입니다\n끝"),
    ("embedded-token", "export FOO=1 aZ3kQ9pL2mX7vB1nC8dF4gH6jK0sT5wY bar"),
]

private let safeCases: [(name: String, text: String)] = [
    ("korean", "오늘 회의는 3시에 시작합니다. 자료는 공유 폴더에 올려두었어요."),
    ("command", "npm run dev"),
    ("git-sha", "9fceb02d0ae598e95dc970b74767f19372d61af7"),
    ("uuid", "123e4567-e89b-12d3-a456-426614174000"),
    ("sha256", "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855"),
    ("url", "https://github.com/example-org/web/pull/123"),
    ("swift", "let manager = ClipboardMonitor(pollInterval: 0.5, policy: CapturePolicy())"),
    ("swift-type", "var token: String = fetchValue()"),
    ("env-ref", "API_KEY=${API_KEY}"),
    ("max-tokens", "max_tokens: 4096"),
    ("kebab", "feature/clipdeck-secret-detector-implementation-v2"),
    ("camel", "UserProfileViewControllerFactory2"),
    ("type-upper", "token: String"),
    ("type-lower", "  token: string;"),
    ("type-optional", "password: String?"),
    ("id-fetch", "fetchUserProfileWithAuth2Token"),
    ("path-abs", "/Users/me/Desktop/project/clipdeck-wt/t5/Sources/ClipdeckCore/SecretDetector.swift"),
    ("path-line", "Sources/ClipdeckCore/SecretDetector.swift:42"),
    ("path-doc", "docs/ADR-0003-SecretDetector-Policy.md"),
    ("path-win", #"C:\Users\Hyo\Documents\Report2026.docx"#),
    ("youtube", "www.youtube.com/watch?v=dQw4w9WgXcQ"),
    ("java-class", "com.example.clipdeck.MainActivity2Kt"),
    ("id-handle", "handleUserAuthenticationCallback2"),
    ("id-nskeyed", "NSKeyedUnarchiverDelegate"),
    ("kebab-branch", "feature-add-clipboard-history-v2-final"),
    ("kv-newline", "token =\n  recalculated later"),
    ("type-optional-generic", "token: Optional<String>"),
    ("type-array", "token: [String]"),
    ("path-components", "src/components/UserProfile2CardView"),
    ("git-ref", "refs/heads/release/2026-11-Hotfix3"),
    ("git-remote", "origin/feature/AS-1310-authFetch-Phase2a"),
    ("repo-path", "example-org/web-frontend-monorepo2"),
    ("type-int64", "count: Int64"),
    ("empty", ""),
]

// 시간 측정 테스트가 같은 스위트의 무거운 검사와 CPU를 다투지 않게 차례로 돌린다
@Suite(.serialized) struct SecretDetectorTests {
    @Test(arguments: detectCases) func detects(_ c: (name: String, text: String)) {
        #expect(SecretDetector.isSecret(c.text), "\(c.name)")
    }

    @Test(arguments: safeCases) func ignores(_ c: (name: String, text: String)) {
        #expect(!SecretDetector.isSecret(c.text), "\(c.name)")
    }

    /// 고정 시드 난수(SplitMix64)로 만든 무작위 키의 탐지율 회귀 방지
    @Test func randomKeysAreMostlyDetected() {
        struct SplitMix64 {
            var state: UInt64
            mutating func next() -> UInt64 {
                state &+= 0x9E37_79B9_7F4A_7C15
                var z = state
                z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
                z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
                return z ^ (z >> 31)
            }
        }
        var rng = SplitMix64(state: 20_261_121)
        func make(_ alphabet: [Character], _ n: Int) -> String {
            String((0..<n).map { _ in alphabet[Int(rng.next() % UInt64(alphabet.count))] })
        }
        let base62 = Array("ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789")
        let base64 = base62 + ["/", "+"]
        let hit62 = (0..<500).filter { _ in SecretDetector.isSecret(make(base62, 32)) }.count
        let hit64 = (0..<500).filter { _ in SecretDetector.isSecret(make(base64, 40)) }.count
        print("detection rate base62x32 = \(hit62)/500, base64x40 = \(hit64)/500")
        #expect(hit62 >= 475)
        #expect(hit64 >= 475)
    }

    @Test(.serialized, arguments: ["token", "password", "token_", "apikey"])
    func keywordRepeatFinishesFast(_ unit: String) {
        let text = String(repeating: unit, count: ClipLimits.plainTextBytes / unit.count)
        let start = Date()
        _ = SecretDetector.isSecret(text)
        let elapsed = Date().timeIntervalSince(start)
        print("keywordRepeat \(unit): \(elapsed)s")
        #expect(elapsed < 2)
    }

    @Test(.serialized, arguments: ["-eyJ", "eyJ", "xeyJ."])
    func jwtPrefixRepeatFinishesFast(_ unit: String) {
        let text = String(repeating: unit, count: ClipLimits.plainTextBytes / unit.count)
        let start = Date()
        _ = SecretDetector.isSecret(text)
        let elapsed = Date().timeIntervalSince(start)
        print("jwtPrefixRepeat \(unit): \(elapsed)s")
        #expect(elapsed < 2)
    }

    private static func jwt(payloadLength: Int) -> String {
        let payload = String(repeating: "aB3dE6gH9jK2", count: payloadLength / 12 + 1).prefix(payloadLength)
        return "ey" + "JhbGciOiJIUzI1NiJ9." + "ey" + payload + "." + "dBjftJeZ4CVPmB92K27uhbUJU1p1r"
    }

    @Test(arguments: [3000, 10_000])
    func detectsLongJWTPayload(_ n: Int) {
        #expect(SecretDetector.isSecret(Self.jwt(payloadLength: n)))
    }

    @Test(arguments: ["x-", "--", "Authorization:Bearer-"])
    func detectsJWTAfterDash(_ prefix: String) {
        #expect(SecretDetector.isSecret(prefix + Self.jwt(payloadLength: 40)))
    }

    @Test func largeTextFinishesFast() {
        let big = String(repeating: "lorem ipsum dolor sit amet ", count: 400_000) // 약 10MB
        let start = Date()
        #expect(!SecretDetector.isSecret(big))
        #expect(Date().timeIntervalSince(start) < 5)
    }

    /// 검사 범위는 MCP에 닿는 범위(앞 100KB)와 같다
    @Test func onlyFirst100KBIsScanned() {
        let pad = String(repeating: "a ", count: 55_000) // 110KB
        #expect(!SecretDetector.isSecret(pad + "gh" + "p_" + body36))
        #expect(SecretDetector.isSecret("gh" + "p_" + body36 + " " + pad))
    }

    /// 64KB 뒤(70KB 지점)의 키도 잡아 MCP에서 숨긴다
    @Test func keyAt70KBIsHidden() {
        let text = String(repeating: "a ", count: 35_000) + "gh" + "p_" + body36 // 키가 70,000바이트 지점
        #expect(SecretDetector.isSecret(text))
        let rep = Representation(uti: PasteboardTypes.plainText, data: Data(text.utf8))
        #expect(ClipBuilder.make(representations: [rep], sourceAppBundleID: nil, sourceAppName: nil,
                                 policy: CapturePolicy())?.mcpHidden == true)
    }

    @Test func builderMarksSecretHidden() {
        let key = Representation(uti: PasteboardTypes.plainText, data: Data(("sk-ant-" + "api03-" + body40).utf8))
        var p = CapturePolicy()
        #expect(ClipBuilder.make(representations: [key], sourceAppBundleID: nil, sourceAppName: nil, policy: p)?.mcpHidden == true)
        p.detectSecrets = false
        #expect(ClipBuilder.make(representations: [key], sourceAppBundleID: nil, sourceAppName: nil, policy: p)?.mcpHidden == false)
        let plain = Representation(uti: PasteboardTypes.plainText, data: Data("npm run dev".utf8))
        #expect(ClipBuilder.make(representations: [plain], sourceAppBundleID: nil, sourceAppName: nil, policy: CapturePolicy())?.mcpHidden == false)
    }

    @Test func builderMarksHiddenApp() {
        let plain = Representation(uti: PasteboardTypes.plainText, data: Data("npm run dev".utf8))
        let p = CapturePolicy(mcpHiddenBundleIDs: ["com.1password.1password"])
        #expect(ClipBuilder.make(representations: [plain], sourceAppBundleID: "com.1password.1password", sourceAppName: nil, policy: p)?.mcpHidden == true)
        #expect(ClipBuilder.make(representations: [plain], sourceAppBundleID: "com.other", sourceAppName: nil, policy: p)?.mcpHidden == false)
    }
}
