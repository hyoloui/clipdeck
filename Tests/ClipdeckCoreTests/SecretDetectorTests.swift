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
    ("empty", ""),
]

@Suite struct SecretDetectorTests {
    @Test(arguments: detectCases) func detects(_ c: (name: String, text: String)) {
        #expect(SecretDetector.isSecret(c.text), "\(c.name)")
    }

    @Test(arguments: safeCases) func ignores(_ c: (name: String, text: String)) {
        #expect(!SecretDetector.isSecret(c.text), "\(c.name)")
    }

    @Test func largeTextFinishesFast() {
        let big = String(repeating: "lorem ipsum dolor sit amet ", count: 400_000) // 약 10MB
        let start = Date()
        #expect(!SecretDetector.isSecret(big))
        #expect(Date().timeIntervalSince(start) < 5)
    }

    @Test func onlyFirst64KBIsScanned() {
        let pad = String(repeating: "a ", count: 40_000) // 80KB
        #expect(!SecretDetector.isSecret(pad + "gh" + "p_" + body36))
        #expect(SecretDetector.isSecret("gh" + "p_" + body36 + " " + pad))
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
