# Clipdeck 구현 계획

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 유료 클립보드 관리자 구독을 대신할 로컬 macOS 클립보드 관리자와, Claude·Codex·agy가 함께 쓰는 stdio MCP 서버를 만든다.

**Architecture:** SwiftPM 패키지 하나에 네 타깃을 둔다. `ClipdeckCore`(저장·검색·캡처 규칙·비밀값 판정·패널 상태·설정), `ClipdeckMCPKit`(MCP 도구와 JSON-RPC 처리), `Clipdeck`(AppKit+SwiftUI 앱), `clipdeck-mcp`(얇은 stdio 실행 파일)이다. 앱과 MCP는 같은 SQLite(WAL) 파일을 공유하고, MCP가 쓰기를 하면 Darwin 알림으로 앱에 알린다.

**Tech Stack:** Swift 6.4(Command Line Tools), SwiftPM, AppKit, SwiftUI, Carbon(전역 단축키), CoreGraphics(CGEvent), 시스템 SQLite3 3.51(FTS5 trigram), CryptoKit, Swift Testing. 외부 패키지는 쓰지 않는다.

**Spec:** `/Users/me/Desktop/cli-temp/docs/superpowers/specs/2026-11-21-clipdeck-design.md` (Task 1에서 저장소 `docs/`로 복사한다)

## Global Constraints

- 저장소: `~/Desktop/project/clipdeck`(git). 설치: `~/Applications/Clipdeck.app`. MCP 실행 파일: `~/Applications/Clipdeck.app/Contents/MacOS/clipdeck-mcp`
- 번들 ID `local.hyoloui.clipdeck`, `LSUIElement = true`, 최소 macOS 14 (`platforms: [.macOS(.v14)]`), `swift-tools-version: 6.0`
- 데이터: `~/Library/Application Support/Clipdeck/clipdeck.sqlite` + `blobs/<sha256>`. 환경변수 `CLIPDECK_DATA_DIR`가 있으면 그 폴더를 쓴다(테스트·MCP 확인용)
- SQLite: WAL, `busy_timeout = 2000`. 64KB를 넘는 표현 데이터는 blob 파일로 저장
- Xcode 없음. 테스트는 `import Testing`만 쓰고 XCTest는 쓰지 않는다
- 서명: 로그인 키체인의 자체 서명 인증서 `Clipdeck Local Signing`만 사용(손쉬운 사용 권한 유지)
- Darwin 알림 이름 `local.hyoloui.clipdeck.db-changed`, 자체 쓰기 표시 UTI `local.hyoloui.clipdeck.self`
- 기본값: 단축키 `⇧⌘V`(전역은 이것 하나), 보관 1개월, 비밀값 자동 숨김 켬, 민감·임시 내용 제외 켬, 화면 공유 중 숨김 켬
- MCP 상한: 목록 기본 20개·최대 100개, 미리보기 200자, `get_item` 텍스트 최대 100KB, 이미지는 긴 변 1024px. 삭제 도구 없음, `mcp_hidden = 1` 항목은 어떤 도구에도 나오지 않음
- 디자인: apple-design 스킬 원칙 + 시스템 의미 색·`NSVisualEffectView`·SF 글꼴. hex 색 하드코딩 금지. 다른 클립보드 앱의 이름·아이콘·화면 모양 금지
- 커밋 메시지 끝에 `Co-Authored-By: Claude Fable 5.2 <noreply@anthropic.com>`

## Review Focus

1. **짧은 한글·특수문자 검색:** "클립", `"`, `*`, `-` 같은 입력도 오류 없이 결과가 나와야 한다. trigram은 3자 미만을 못 찾으므로 3자 미만은 LIKE로 대체한다(Task 3 테스트).
2. **아주 큰 복사:** 10MB 텍스트나 큰 이미지도 저장되고, 미리보기는 300자로 잘리며, DB 행에는 blob 경로만 남아야 한다(Task 2·5 테스트).
3. **잘못된 MCP 입력:** JSON이 깨진 줄, 모르는 메서드, 인자 타입 오류가 와도 서버가 죽지 않고 JSON-RPC 오류를 돌려줘야 한다(Task 8 테스트).
4. **동시 접근:** 앱이 쓰는 중에 MCP가 읽어도 `database is locked` 없이 동작해야 한다(Task 2 테스트).
5. **비어 있거나 지원하지 않는 클립보드:** 비공개 UTI만 있는 복사는 조용히 건너뛰어야 한다(Task 5 테스트).

---

### Task 1: 패키지 뼈대, SQLite 래퍼, 스키마

**Files:**
- Create: `Package.swift`, `.gitignore`, `docs/spec.md`(스펙 복사), `docs/plan.md`(이 계획 복사)
- Create: `Sources/ClipdeckCore/SQLite.swift`, `Sources/ClipdeckCore/Schema.swift`, `Sources/ClipdeckCore/Models.swift`
- Create: 빈 진입점 `Sources/ClipdeckMCPKit/Placeholder.swift`, `Sources/Clipdeck/main.swift`, `Sources/clipdeck-mcp/main.swift`
- Test: `Tests/ClipdeckCoreTests/SchemaTests.swift`

**Interfaces:**
- Produces:
  - `public enum SQLValue { case null, int(Int64), double(Double), text(String), blob(Data) }`
  - `public final class Database { public init(path: String) throws; public func execute(_ sql: String, _ params: [SQLValue] = []) throws; public func query(_ sql: String, _ params: [SQLValue] = []) throws -> [[String: SQLValue]]; public var lastInsertRowID: Int64 { get }; public func transaction<T>(_ body: () throws -> T) throws -> T }`
  - `public enum Schema { public static let version: Int32 = 1; public static func migrate(_ db: Database) throws }`
  - `Models.swift`: `ItemKind`(text, link, image, file, color), `ClipItem`, `Representation(uti: String, data: Data)`, `NewClip`, `InsertResult`(.inserted(Int64), .bumped(Int64)), `Pinboard(id, name, color: String?, sort, itemCount)`, `SearchQuery(text = "", kind: ItemKind?, appBundleID: String?, pinboardID: Int64?, since: Date?, limit = 50)` — 필드는 스펙 §6.2 `items` 컬럼과 같은 이름(camelCase)
- 타깃: 라이브러리 `ClipdeckCore`, `ClipdeckMCPKit`(Core 의존), 실행 파일 `Clipdeck`(Core 의존), `clipdeck-mcp`(MCPKit 의존). `ClipdeckCore`는 `linkerSettings: [.linkedLibrary("sqlite3")]`, `import SQLite3`

- [ ] **Step 1:** `mkdir ~/Desktop/project/clipdeck && cd ~/Desktop/project/clipdeck && git init`, 스펙·계획을 `docs/`로 복사
- [ ] **Step 2: 실패하는 테스트 작성**

```swift
@Test func migrateCreatesSchemaInWALMode() throws {
    let dir = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    let db = try Database(path: dir.appending(path: "t.sqlite").path)
    try Schema.migrate(db)
    #expect(try db.query("PRAGMA user_version").first?["user_version"] == .int(1))
    #expect(try db.query("PRAGMA journal_mode").first?["journal_mode"] == .text("wal"))
    let names = try db.query("SELECT name FROM sqlite_master").compactMap { if case .text(let s) = $0["name"] { s } else { nil } }
    for t in ["items", "item_representations", "pinboards", "pinboard_items", "items_fts"] { #expect(names.contains(t)) }
    try Schema.migrate(db) // 두 번 실행해도 오류 없음
}
```

- [ ] **Step 3:** `swift test --filter SchemaTests` → 컴파일 실패 확인
- [ ] **Step 4: 구현.** `Database`는 `sqlite3_open_v2`(FULLMUTEX)로 열고 `journal_mode=WAL`, `busy_timeout=2000`, `foreign_keys=ON`을 설정한다. 스키마:
  - `items(id INTEGER PRIMARY KEY, kind TEXT, preview TEXT, plain_text TEXT, content_hash TEXT UNIQUE, source_app_bundle_id TEXT, source_app_name TEXT, mcp_hidden INTEGER DEFAULT 0, created_at REAL, last_used_at REAL, use_count INTEGER DEFAULT 0)`
  - `item_representations(item_id REFERENCES items ON DELETE CASCADE, uti TEXT, data BLOB, blob_path TEXT)`
  - `pinboards(id, name TEXT UNIQUE, color TEXT, sort INTEGER)`
  - `pinboard_items(pinboard_id REFERENCES pinboards ON DELETE CASCADE, item_id REFERENCES items ON DELETE CASCADE, PRIMARY KEY(pinboard_id, item_id))`
  - `items_fts`: `fts5(plain_text, content='items', content_rowid='id', tokenize='trigram')` + insert·update·delete 트리거
  - `user_version`이 1보다 작을 때만 생성
- [ ] **Step 5:** `swift test --filter SchemaTests` → PASS, `swift build` → 네 타깃 모두 빌드
- [ ] **Step 6:** 커밋 `chore: SwiftPM 패키지와 SQLite 스키마 추가`

### Task 2: ClipStore 저장·중복 처리·blob·동시 접근

**Files:**
- Create: `Sources/ClipdeckCore/ClipStore.swift`
- Test: `Tests/ClipdeckCoreTests/ClipStoreTests.swift`, `Tests/ClipdeckCoreTests/TestSupport.swift`(`makeTempStore() -> (ClipStore, URL)`, `textClip(_ s: String, app: String? = nil, hidden: Bool = false) -> NewClip` 헬퍼)

**Interfaces:**
- Consumes: Task 1의 `Database`, `Schema`, 모델
- Produces:
  - `public final class ClipStore: @unchecked Sendable { public init(directory: URL) throws; public static func defaultDirectory() -> URL }`
  - `insert(_ clip: NewClip, now: Date = .now) throws -> InsertResult`
  - `item(id: Int64) throws -> ClipItem?`, `representations(itemID: Int64) throws -> [Representation]`, `plainText(itemID: Int64) throws -> String?`
  - `markUsed(id: Int64, now: Date = .now) throws`, `delete(id: Int64) throws`, `eraseHistory() throws`, `setMCPHidden(id: Int64, _ hidden: Bool) throws`, `hideFromMCP(appBundleID: String) throws`

- [ ] **Step 1: 실패하는 테스트 작성**
  - `insertThenReadBack`: 텍스트를 넣고 읽으면 kind·preview·출처 앱이 같다
  - `duplicateHashBumps`: 같은 hash를 t0, t1에 넣으면 두 번째는 `.bumped(id)`이고 `lastUsedAt == t1`, 항목 수 1
  - `largeRepresentationGoesToBlob`: 10MB 데이터를 넣으면 `item_representations.data`는 NULL, `blobs/<sha256>` 파일이 있고, `representations()`가 원본 바이트를 돌려준다
  - `eraseHistoryKeepsPinboardItems`: Pinboard에 넣은 항목만 남는다(Task 4의 `add(itemID:toPinboard:)`는 아직 없으므로 SQL로 직접 넣는다)
  - `deleteRemovesBlob`: 마지막 참조가 지워지면 blob 파일도 지워진다
  - `hideFromMCPMarksExistingItems`: 해당 앱의 기존 항목이 모두 `mcpHidden == true`
  - `concurrentReaderDoesNotLock`: 같은 폴더로 `ClipStore`를 2개 열고, 한쪽이 200회 insert하는 동안 다른 쪽이 200회 `item(id:)`를 호출한다. 예외가 없어야 한다
- [ ] **Step 2:** `swift test --filter ClipStoreTests` → FAIL
- [ ] **Step 3: 구현.** 쓰기는 `transaction` 안에서 한다. `defaultDirectory()`는 `CLIPDECK_DATA_DIR` 또는 `~/Library/Application Support/Clipdeck`이고, 폴더가 없으면 만든다.
- [ ] **Step 4:** `swift test --filter ClipStoreTests` → PASS
- [ ] **Step 5:** 커밋 `feat(core): ClipStore 저장과 중복 처리`

### Task 3: 검색(FTS trigram + 짧은 질의 LIKE + 필터)

**Files:**
- Create: `Sources/ClipdeckCore/ClipStore+Search.swift`
- Test: `Tests/ClipdeckCoreTests/SearchTests.swift`

**Interfaces:**
- Produces: `public func search(_ q: SearchQuery) throws -> [ClipItem]`. 텍스트가 비어 있으면 최근 사용 순 목록이고, 정렬은 언제나 `last_used_at DESC`, `LIMIT q.limit`이다. `internal func searchSQL(_ q: SearchQuery, extraWhere: String?) -> (String, [SQLValue])`는 Task 7이 재사용한다.

- [ ] **Step 1: 실패하는 테스트 작성**
  - `koreanTrigram`: "클립보드 기록 정리"를 "클립보"로 검색하면 1건
  - `shortQueryFallsBackToLike`: "클립"(2자)과 "a"로도 찾는다
  - `specialCharactersDoNotThrow`: `"`, `*`, `-`, `NEAR(`, `'` 각각 검색해도 예외가 없다(FTS 질의는 큰따옴표 구문으로 감싸 이스케이프)
  - `filtersCombine`: kind=.link + appBundleID + since 조합이 맞게 걸러진다
  - `pinboardFilter`: pinboardID로 해당 보드 항목만 나온다
  - `orderByLastUsed`: `markUsed`된 항목이 맨 앞에 온다
- [ ] **Step 2:** `swift test --filter SearchTests` → FAIL
- [ ] **Step 3:** 구현. 3자 이상이면 `items_fts MATCH ?`, 미만이면 `plain_text LIKE ? ESCAPE '\'`를 쓴다.
- [ ] **Step 4:** `swift test --filter SearchTests` → PASS
- [ ] **Step 5:** 커밋 `feat(core): 검색과 필터`

### Task 4: Pinboard와 보관 정리

**Files:**
- Create: `Sources/ClipdeckCore/ClipStore+Pinboards.swift`, `Sources/ClipdeckCore/Retention.swift`
- Test: `Tests/ClipdeckCoreTests/PinboardTests.swift`, `Tests/ClipdeckCoreTests/RetentionTests.swift`

**Interfaces:**
- Produces:
  - `createPinboard(name: String, color: String?) throws -> Int64`, `renamePinboard(id: Int64, name: String) throws`, `deletePinboard(id: Int64) throws`, `pinboards() throws -> [Pinboard]`(sort 순, itemCount 포함), `pinboard(named: String) throws -> Pinboard?`
  - `add(itemID: Int64, toPinboard: Int64) throws`(중복 무시), `remove(itemID: Int64, fromPinboard: Int64) throws`
  - `purge(olderThan cutoff: Date) throws -> Int`: Pinboard에 없는 항목만 지운다
  - `public enum RetentionPeriod: String, Codable, CaseIterable { case day, week, month, year, forever; public func cutoff(from now: Date) -> Date? }`(forever는 nil, month는 `Calendar.current`로 1개월 전)

- [ ] **Step 1: 실패하는 테스트 작성**
  - `pinboardCRUD`: 만들기, 이름 바꾸기, 목록 itemCount, 삭제했을 때 항목 자체는 남음
  - `duplicateNameThrows`
  - `purgeKeepsPinned`: 40일 전 항목 2개 중 고정한 1개만 남고, 반환값은 1
  - `cutoffValues`: `.day`는 정확히 86400초 전, `.forever`는 nil
- [ ] **Step 2:** `swift test --filter "PinboardTests|RetentionTests"` → FAIL
- [ ] **Step 3:** 구현
- [ ] **Step 4:** `swift test --filter "PinboardTests|RetentionTests"` → PASS
- [ ] **Step 5:** 커밋 `feat(core): Pinboard와 보관 정리`

### Task 5: 캡처 규칙, 종류 판정, ClipBuilder

**Files:**
- Create: `Sources/ClipdeckCore/CapturePolicy.swift`, `Sources/ClipdeckCore/KindClassifier.swift`, `Sources/ClipdeckCore/ClipBuilder.swift`
- Test: `Tests/ClipdeckCoreTests/CaptureTests.swift`

**Interfaces:**
- Produces:
  - `public enum PasteboardTypes { selfMarker = "local.hyoloui.clipdeck.self", concealed = "org.nspasteboard.ConcealedType", transient = "org.nspasteboard.TransientType", autoGenerated = "org.nspasteboard.AutoGeneratedType", fileURL = "public.file-url", png = "public.png", tiff = "public.tiff", color = "com.apple.cocoa.pasteboard.color", plainText = "public.utf8-plain-text", rtf = "public.rtf", html = "public.html", url = "public.url" }`
  - `public struct CapturePolicy: Codable, Equatable, Sendable { var ignoreConcealed = true; var ignoreTransient = true; var ignoredBundleIDs: Set<String>; var mcpHiddenBundleIDs: Set<String> = []; var detectSecrets = true; var pausedUntil: Date? }`. `pausedUntil == .distantFuture`이면 무기한 일시정지
  - `public enum SkipReason { case concealed, transient, ignoredApp, paused, selfWrite, empty }`, `public enum CaptureDecision: Equatable { case capture, skip(SkipReason) }`
  - `func decide(types: [String], frontmostBundleID: String?, now: Date) -> CaptureDecision`. 판단 순서: selfWrite → paused → ignoredApp → concealed → transient·autoGenerated
  - `public enum KindClassifier { static func classify(utis: [String], plainText: String?) -> ItemKind? }`. 순서는 fileURL → png/tiff → color → link(텍스트 전체가 http/https URL) → text이고, 해당 없으면 nil
  - `public enum ClipBuilder { static func make(representations: [Representation], sourceAppBundleID: String?, sourceAppName: String?, policy: CapturePolicy) -> NewClip? }`. hash는 기본 표현(텍스트=plain_text UTF-8, 이미지=png/tiff 데이터, 파일=URL 목록, 색=색 데이터)의 SHA256이다. 미리보기 규칙:
    - 텍스트: 공백을 한 칸으로 줄이고 300자로 자름
    - 이미지: "이미지 W×H"(ImageIO)
    - 파일: 파일 이름을 ", "로 연결
    - 색: "#RRGGBB"
  - `mcpHidden`은 Task 6에서 채운다(이 Task에서는 `policy.mcpHiddenBundleIDs`만 반영)

- [ ] **Step 1: 실패하는 테스트 작성**
  - `decideOrder`: 표에 정리한 입력마다 기대한 `SkipReason`이 나온다(자체 표시 + 일시정지가 함께 있으면 selfWrite, 제외 앱 + concealed가 함께 있으면 ignoredApp)
  - `pausedExpires`: `pausedUntil`이 과거면 capture
  - `classifyOrder`: 파일 URL과 텍스트가 함께 있으면 .file, "https://a.com"이면 .link, "see https://a.com"이면 .text
  - `privateOnlyIsNil`: `["com.example.private"]`만 있으면 `make`가 nil
  - `hugeTextPreviewTruncated`: 10MB 텍스트의 preview가 300자 이하
  - `sameTextSameHash`
- [ ] **Step 2:** `swift test --filter CaptureTests` → FAIL
- [ ] **Step 3:** 구현
- [ ] **Step 4:** `swift test --filter CaptureTests` → PASS
- [ ] **Step 5:** 커밋 `feat(core): 캡처 규칙과 항목 생성`

### Task 6: 비밀값 판정과 MCP 숨김 표시

**Files:**
- Create: `Sources/ClipdeckCore/SecretDetector.swift`
- Modify: `Sources/ClipdeckCore/ClipBuilder.swift`(`policy.detectSecrets && SecretDetector.isSecret(plainText)`이면 `mcpHidden = true`)
- Test: `Tests/ClipdeckCoreTests/SecretDetectorTests.swift`

**Interfaces:**
- Produces: `public enum SecretDetector { public static func isSecret(_ text: String) -> Bool }`

- [ ] **Step 1: 실패하는 테스트 작성** (탐지와 오탐 각각 `@Test(arguments:)`)
  - 탐지해야 함:
    - 접두사형 키: `sk-ant-api03-` + 40자, `sk-proj-` + 40자, `ghp_` + 36자, `github_pat_` + 82자, `xoxb-1234-5678-abcd`, `AKIA` + 16자 대문자·숫자, `AIza` + 35자
    - 토큰·키 블록: JWT 3조각, `-----BEGIN OPENSSH PRIVATE KEY-----`가 들어간 여러 줄
    - 키-값 형태: `DB_PASSWORD=hunter2hunter2`, `api_key: "Zx9…"`
    - 고엔트로피: 공백 없는 32자 혼합 문자열 `aZ3kQ9pL2mX7vB1nC8dF4gH6jK0sT5wY`
  - 탐지하면 안 됨:
    - 일반 문장: 한국어 문장, `npm run dev`
    - 식별자·해시: git SHA 40자 hex, UUID, sha256 64자 hex
    - URL: `https://github.com/example-org/web/pull/123`
    - 코드: Swift 코드 한 줄
  - `builderMarksSecretHidden`: `ClipBuilder.make`가 API 키 텍스트를 받으면 `mcpHidden == true`, `detectSecrets = false`면 false
  - `builderMarksHiddenApp`: `mcpHiddenBundleIDs`에 든 앱에서 온 항목은 `mcpHidden == true`
- [ ] **Step 2:** `swift test --filter SecretDetectorTests` → FAIL
- [ ] **Step 3: 구현.** 접두사·형식 정규식 + 키-값 정규식(`(?i)(password|passwd|secret|token|api[_-]?key)\s*[:=]\s*\S{6,}`) + 고엔트로피 판정을 둔다. 고엔트로피 조건:
  - 공백 없는 토큰이 24자 이상
  - 대문자·소문자·숫자를 모두 포함
  - Shannon 엔트로피 4.0 bit/문자 이상
  - URL(`://` 포함), 순수 hex, UUID 형식은 제외

  오탐 테스트가 실패하면 기준값을 바꾸고, 바꾼 값을 코드 주석에 남긴다.
- [ ] **Step 4:** `swift test --filter "SecretDetectorTests|CaptureTests"` → PASS
- [ ] **Step 5:** 커밋 `feat(core): 비밀값 판정과 MCP 숨김 표시`

### Task 7: MCP 전용 조회와 도구 핸들러

**Files:**
- Create: `Sources/ClipdeckCore/ClipStore+MCP.swift`(숨김 제외 조회는 이 파일에서만 한다)
- Create: `Sources/ClipdeckMCPKit/JSONValue.swift`, `Sources/ClipdeckMCPKit/ToolRegistry.swift`, `Sources/ClipdeckMCPKit/ClipboardWriting.swift`
- Test: `Tests/ClipdeckMCPKitTests/ToolRegistryTests.swift`

**Interfaces:**
- Consumes: `search`/`searchSQL`, Pinboard API, `SecretDetector`, `ClipBuilder`
- Produces:
  - `extension ClipStore { public func mcpSearch(_ q: SearchQuery) throws -> [ClipItem]; public func mcpItem(id: Int64) throws -> ClipItem?; public func mcpPinboards() throws -> [Pinboard] }`. `mcp_hidden = 0` 조건을 붙이고, Pinboard의 itemCount도 보이는 항목만 센다
  - `public indirect enum JSONValue: Codable, Equatable { case null, bool(Bool), number(Double), string(String), array([JSONValue]), object([String: JSONValue]) }`
  - `public protocol ClipboardWriting { func write(_ representations: [Representation]) }`, `public struct SystemClipboard: ClipboardWriting`(NSPasteboard에 쓰고 `selfMarker`는 붙이지 않는다. MCP로 복사한 내용도 기록에 남게 하기 위해서다)
  - `public struct ToolDefinition { name: String; description: String; inputSchema: JSONValue }`, `public enum ToolContent { case text(String), image(base64: String, mimeType: String) }`, `public struct ToolResult { content: [ToolContent]; isError: Bool }`
  - `public final class ToolRegistry { public init(store: ClipStore, clipboard: ClipboardWriting, notifyChange: @escaping () -> Void); public var definitions: [ToolDefinition]; public func call(name: String, arguments: [String: JSONValue]) -> ToolResult }`
  - 도구 8개와 인자는 스펙 §6.7 표 그대로다:
    - 목록 도구: `search_items`, `list_recent`, `list_pinboards`, `list_pinboard_items`
    - 조회 도구: `get_item`
    - 쓰기 도구: `copy_to_clipboard`, `create_text_item`, `add_to_pinboard`
  - 인자 `pinboard`는 id(숫자) 또는 이름(문자열)을 받는다. 없는 보드면 `isError`로 "보드 없음"을 돌려주고, 새로 만들지 않는다.
  - 목록 결과는 JSON 텍스트 배열이고, 각 항목은 `{id, kind, preview(200자), app, last_used_at(ISO8601)}`다. 쓰기 도구는 성공한 뒤 `notifyChange()`를 호출한다. 텍스트 설명(description)은 한국어와 영어를 함께 적는다.

- [ ] **Step 1: 실패하는 테스트 작성** (가짜 `ClipboardWriting`이 쓴 내용을 기록)
  - `hiddenNeverAppears`: 숨김 항목 1개 + 일반 항목 1개를 만든다. 다음 각 경로로 호출해 숨김 항목의 id와 미리보기가 결과 문자열에 나오지 않아야 한다
    - 목록: `search_items`(그 항목의 텍스트로 검색), `list_recent`, `list_pinboard_items`
    - 조회: `get_item(id: 숨김)`, `copy_to_clipboard(id: 숨김)`
    - 보드 개수: `list_pinboards`의 itemCount
  - `get_item`과 `copy_to_clipboard`는 "항목 없음" 오류(`isError == true`)를 돌려야 한다
  - `limitClamped`: `limit: 500`이면 100개, 기본은 20개
  - `getItemTruncates`: 150KB 텍스트는 100KB로 잘리고 잘림 안내가 붙는다
  - `getItemImageScaled`: 2048×1024 PNG를 넣으면 `.image` 콘텐츠가 나오고 디코드한 크기가 1024×512
  - `createTextItemRunsSecretCheck`: API 키로 만든 항목은 `list_recent`에 나오지 않고, `notifyChange`는 1회 호출된다
  - `copyToClipboardWritesReps`: 일반 항목이면 가짜 클립보드에 원본 표현이 기록된다
  - `noDeleteTool`: `definitions`에 delete, remove, erase가 들어간 이름이 없다
  - `badArgumentsIsError`: `get_item(id: "abc")`는 `isError == true`이고 크래시하지 않는다
- [ ] **Step 2:** `swift test --filter ToolRegistryTests` → FAIL
- [ ] **Step 3:** 구현
- [ ] **Step 4:** `swift test --filter ToolRegistryTests` → PASS
- [ ] **Step 5:** 커밋 `feat(mcp): MCP 도구와 숨김 항목 차단`

### Task 8: JSON-RPC stdio 서버와 `clipdeck-mcp`

**Files:**
- Create: `Sources/ClipdeckMCPKit/JSONRPCServer.swift`
- Modify: `Sources/clipdeck-mcp/main.swift`
- Test: `Tests/ClipdeckMCPKitTests/JSONRPCServerTests.swift`

**Interfaces:**
- Consumes: `ToolRegistry`
- Produces: `public final class JSONRPCServer { public init(tools: ToolRegistry, serverName: String = "clipdeck", version: String); public func handle(line: String) -> String? }`(알림이면 nil). 줄 단위 JSON(stdio MCP 전송)을 처리한다. 지원 메서드:
  - `initialize`: 클라이언트 `protocolVersion`이 `2025-06-18`, `2025-03-26`, `2024-11-05` 중 하나면 그대로 돌려주고, 아니면 `2025-06-18`. `capabilities: {tools: {}}`
  - `notifications/initialized`, `ping`, `tools/list`, `tools/call`

  오류 코드: 파싱 실패 -32700, 모르는 메서드 -32601, 인자 오류 -32602
- `main.swift`: `ClipStore(directory: ClipStore.defaultDirectory())`와 `SystemClipboard`를 쓴다. `notifyChange`는 `CFNotificationCenterPostNotification(CFNotificationCenterGetDarwinNotifyCenter(), "local.hyoloui.clipdeck.db-changed", …)`이다. stdin을 한 줄씩 읽어 응답을 stdout에 쓰고 flush한다. 로그는 stderr로만 보낸다.

- [ ] **Step 1: 실패하는 테스트 작성**
  - `initializeEchoesVersion`, `toolsListHasEight`
  - `malformedLineReturnsParseError`: `"{oops"`에 id null, code -32700으로 응답하고, 그다음 `ping`도 정상 응답한다
  - `unknownMethod`: -32601
  - `notificationReturnsNil`
  - `toolsCallRoundTrip`: `list_recent`의 result.content[0].type이 "text"
- [ ] **Step 2:** `swift test --filter JSONRPCServerTests` → FAIL
- [ ] **Step 3:** 구현
- [ ] **Step 4:** `swift test` → 전체 PASS
- [ ] **Step 5: 실제 실행 확인.** 아래 명령의 출력 두 줄 중 두 번째에 도구 이름 8개가 있어야 한다.

```bash
export CLIPDECK_DATA_DIR=$(mktemp -d)
printf '%s\n' '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2025-06-18","capabilities":{},"clientInfo":{"name":"t","version":"0"}}}' '{"jsonrpc":"2.0","id":2,"method":"tools/list"}' | swift run clipdeck-mcp
```

- [ ] **Step 6:** 커밋 `feat(mcp): stdio JSON-RPC 서버`

### Task 9: 앱 셸 — 메뉴바, 클립보드 감시, 번들·서명 스크립트

**Files:**
- Create: `Resources/Info.plist`(Global Constraints 값 + `CFBundleExecutable = Clipdeck`, `CFBundleIconFile = AppIcon`)
- Create: `Resources/AppIcon.icns`(직접 만든 간단한 아이콘. 다른 클립보드 앱과 닮지 않게, `sips`/`iconutil`로 생성)
- Create: `scripts/make-signing-cert.sh`, `scripts/bundle.sh`
- Create: `Sources/Clipdeck/main.swift`, `Sources/Clipdeck/AppDelegate.swift`, `Sources/Clipdeck/Capture/PasteboardMonitor.swift`, `Sources/Clipdeck/MenuBar/StatusItemController.swift`
- Create: `Sources/ClipdeckCore/AppSettings.swift`
- Test: `Tests/ClipdeckCoreTests/AppSettingsTests.swift`

**Interfaces:**
- Consumes: `ClipStore`, `CapturePolicy`, `ClipBuilder`, `RetentionPeriod`
- Produces:
  - `public struct HotKeySpec: Codable, Equatable { keyCode: UInt32; carbonModifiers: UInt32; static let openPanel = HotKeySpec(keyCode: 9, carbonModifiers: 768) }`(⇧⌘V)
  - `public struct KeyChord: Codable, Equatable { keyCode: UInt16; modifiers: UInt }`
  - `public struct PanelKeyBindings: Codable, Equatable { plainText = ⇧↩, nextBoard = Tab, previousBoard = ⇧Tab }`
  - `public struct AppSettings: Codable, Equatable`의 필드와 기본값:

    | 필드 | 기본값 |
    |---|---|
    | `retention` | `.month` |
    | `pasteToActiveApp` | `true` |
    | `alwaysPlainText` | `false` |
    | `soundEffects` | `true` |
    | `showMenuBarIcon` | `true` |
    | `hideDuringScreenSharing` | `true` |
    | `openAtLogin` | `true` |
    | `hotKey` | `.openPanel` |
    | `panelKeys` | `PanelKeyBindings()` |
    | `capture` | `CapturePolicy(ignoredBundleIDs: AppSettings.defaultIgnoredApps)` |

  - `defaultIgnoredApps`: 이 맥의 `/Applications`와 `/System/Applications`에서 키체인 접근, 암호, 1Password, Bitwarden 등을 찾아 실제 번들 ID로 채운다
  - `public final class SettingsStore { public init(defaults: UserDefaults = .standard); public func load() -> AppSettings; public func save(_ s: AppSettings) }`
  - 앱 내부 클래스:
    - `PasteboardMonitor(store:settings:onCapture:)`: 0.5초 `Timer`로 `changeCount`를 확인한다. 앞 앱은 `NSWorkspace.shared.frontmostApplication`이다. `.skip(.selfWrite)`이면 아무것도 하지 않는다(사용 기록 갱신은 `PasteService`가 한다).
    - `StatusItemController`: 메뉴에 다음 항목을 둔다.
      - 열기
      - 일시정지: 15분·1시간·8시간·무기한
      - 재개
      - 설정…
      - 기록 전체 삭제…(확인 창)
      - 종료

- [ ] **Step 1: 실패하는 테스트 작성** — `AppSettingsTests`: 기본값이 위 목록과 같고, 저장한 뒤 다시 읽으면 같으며, 알 수 없는 키가 있는 JSON도 읽힌다(디코딩 실패하면 기본값).
- [ ] **Step 2:** `swift test --filter AppSettingsTests` → FAIL → 구현 → PASS
- [ ] **Step 3: 서명 인증서 스크립트 작성.** `scripts/make-signing-cert.sh`가 하는 일:
  - `openssl`로 코드 서명 EKU를 넣은 자체 서명 인증서를 만든다
  - `security import`로 로그인 키체인에 넣고 `codesign` 신뢰를 설정한다
  - 이미 있으면 아무것도 하지 않는다

  실행할 때 키체인 승인 창이 뜨면 사용자에게 승인을 요청한다.
- [ ] **Step 4: 번들 스크립트 작성.** `scripts/bundle.sh`가 하는 일:
  1. `swift build -c release`
  2. `~/Applications/Clipdeck.app/Contents/{MacOS,Resources}`를 만들고 `Clipdeck`, `clipdeck-mcp`, Info.plist, 아이콘을 복사
  3. `codesign --force --options runtime --sign "Clipdeck Local Signing"`으로 `clipdeck-mcp`를 먼저, 앱을 나중에 서명
  4. 실행 중인 앱을 종료한 뒤 `open`으로 다시 실행
- [ ] **Step 5: 확인.** 다음 다섯 가지를 확인한다.
  1. `scripts/bundle.sh` 후 메뉴바에 아이콘이 뜨고, Dock에는 없다
  2. `echo hello-clipdeck | pbcopy`를 1초 기다린 뒤 실행한 `sqlite3 ~/Library/Application\ Support/Clipdeck/clipdeck.sqlite "select preview from items order by last_used_at desc limit 1"`의 출력이 `hello-clipdeck`
  3. 일시정지 중 복사한 내용은 저장되지 않는다
  4. `codesign -dv ~/Applications/Clipdeck.app 2>&1 | grep Authority`의 출력이 `Clipdeck Local Signing`
  5. 다시 빌드해도 2번이 그대로 동작한다
- [ ] **Step 6:** 커밋 `feat(app): 메뉴바 앱과 클립보드 감시`

### Task 10: 패널 — PanelModel, 화면, 전역 단축키

**Files:**
- Create: `Sources/ClipdeckCore/PanelModel.swift`
- Create: `Sources/Clipdeck/Panel/PanelController.swift`, `Sources/Clipdeck/Panel/PanelView.swift`, `Sources/Clipdeck/Panel/ItemRow.swift`, `Sources/Clipdeck/Panel/PreviewView.swift`, `Sources/Clipdeck/Design/Layout.swift`, `Sources/Clipdeck/HotKey/GlobalHotKey.swift`
- Test: `Tests/ClipdeckCoreTests/PanelModelTests.swift`

**Interfaces:**
- Consumes: `search`, `pinboards`, `AppSettings.panelKeys`
- Produces:
  - `@MainActor public final class PanelModel: ObservableObject { @Published public var query: String; @Published public private(set) var items: [ClipItem]; @Published public private(set) var selectedIndex: Int; @Published public private(set) var boardIndex: Int; public private(set) var boards: [Pinboard]; public init(store: ClipStore); public func reload(); public func moveSelection(_ delta: Int); public func selectNextBoard(); public func selectPreviousBoard(); public var selectedItem: ClipItem? { get }; public func item(atShortcut n: Int) -> ClipItem? }`
    - `boardIndex` 0은 "기록"이고, 1부터는 `boards[i-1]`이다
    - `query`를 바꾸면 즉시 `reload`한다(디바운스 없음)
    - 화면 표시는 첫 200개까지
  - `final class GlobalHotKey { init(spec: HotKeySpec, handler: @escaping () -> Void); func update(_ spec: HotKeySpec) }`(Carbon `RegisterEventHotKey`)
  - `final class PanelController { func toggle(); func show(); func hide() }`
    - 패널: `NSPanel(styleMask: [.nonactivatingPanel, .titled, .fullSizeContentView])`, 레벨 `.floating`, `collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]`, 크기 760×480, 활성 화면 중앙
    - `hideDuringScreenSharing`이면 `sharingType = .none`
    - 패널 밖을 클릭하거나 포커스를 잃으면 닫는다
- 화면: 스펙 §6.4 스케치대로 구성하고, 스펙 §6.9 규칙(시스템 색, `NSVisualEffectView` `.hudWindow`, 스프링 `response 0.3 / damping 0.85`, Reduce Motion이면 페이드만)을 따른다. 행 구성:
  - 순번(1–9)
  - 종류 아이콘(SF Symbols)
  - 미리보기
  - 출처 앱
  - 상대 시각
  - `mcpHidden` 항목: 자물쇠 표시를 하고, 미리보기는 앞 4자 + "••••". 미리보기 영역의 "보기" 버튼을 눌러야 펼친다
- 키 처리: `NSEvent.addLocalMonitorForEvents`. 다음 키는 Task 11의 `PasteService`를 호출한다.
  - ↩, ⇧↩, ⌘1–9, 더블클릭
  - ⌘P(보드 선택 메뉴), ⌫, ⌘C
  - 항목별 MCP 숨김 전환(⌘H)

  Esc는 닫기다.

- [ ] **Step 1: 실패하는 테스트 작성**
  - `selectionClamps`: 0에서 -1 이동은 0, 끝에서 +1 이동은 끝
  - `queryResetsSelection`: 검색어를 바꾸면 선택 위치가 0
  - `boardCycling`: 보드가 2개면 0→1→2→0, previous는 0→2
  - `shortcutIndex`: `item(atShortcut: 1)`은 맨 위 항목, 10이나 범위 밖은 nil
  - `boardFiltersItems`: 보드 1을 선택하면 그 보드 항목만 나온다
- [ ] **Step 2:** `swift test --filter PanelModelTests` → FAIL → 구현 → PASS
- [ ] **Step 3: 화면 구현.** 구현하기 전에 `apple-design` 스킬을 읽는다. 하드코딩한 색이 없는지 `grep -rnE '#[0-9A-Fa-f]{6}|Color\(red' Sources/Clipdeck`로 확인하고, 출력이 없어야 한다.
- [ ] **Step 4: 확인.** 먼저 다른 클립보드 앱을 종료한다(같은 단축키를 쓰기 때문이다). 그다음 `scripts/bundle.sh`를 실행하고 다음을 확인한다.
  - ⇧⌘V를 누르면 패널이 바로 뜨고, 검색창에 커서가 있다
  - 타이핑하면 목록이 즉시 걸러진다
  - Tab으로 보드를 전환할 수 있다
  - Esc로 닫힌다
  - 다크/라이트 모드를 바꿔도 색이 자연스럽다
- [ ] **Step 5:** 커밋 `feat(app): 검색 패널과 전역 단축키`

### Task 11: 붙여넣기 서비스

**Files:**
- Create: `Sources/ClipdeckCore/PastePayload.swift`, `Sources/Clipdeck/Paste/PasteService.swift`, `Sources/Clipdeck/Paste/AccessibilityPermission.swift`
- Test: `Tests/ClipdeckCoreTests/PastePayloadTests.swift`

**Interfaces:**
- Consumes: `representations(itemID:)`, `markUsed`, `PanelController`, `AppSettings`
- Produces:
  - `public enum PastePayload { public static func build(_ reps: [Representation], plainTextOnly: Bool) -> [Representation] }`: 항상 `selfMarker` 표현(빈 Data)을 덧붙인다. `plainTextOnly`면 `public.utf8-plain-text`만 남긴다. 텍스트가 없으면 원본 그대로다.
  - `final class PasteService { func rememberFrontmostApp(); func paste(itemID: Int64, plainText: Bool); func copyOnly(itemID: Int64) }`
    - `paste`의 순서: 스펙 §6.5의 1–4단계 → `markUsed` → 효과음(`NSSound(named: "Pop")`, 설정이 켜져 있을 때)
    - ⌘V 전송: `CGEvent(keyboardEventSource:virtualKey: 9, keyDown:)`에 `.maskCommand`, `post(tap: .cghidEventTap)`. 앞 앱을 활성화한 뒤 50ms 후에 보낸다(활성화가 끝나기 전에 키가 가지 않게)
  - `enum AccessibilityPermission { static var isTrusted: Bool; static func prompt() }`: `AXIsProcessTrustedWithOptions`를 쓰고, 시스템 설정의 손쉬운 사용 화면 URL을 연다
  - 권한이 없거나 `pasteToActiveApp == false`면 복사만 하고 "클립보드에 복사됨" 알림을 띄운다. 권한이 없을 때는 알림에 "권한 열기" 버튼을 붙인다.

- [ ] **Step 1: 실패하는 테스트 작성** — `plainTextStripsRichTypes`, `markerAlwaysAppended`, `imageOnlyUnchangedWhenPlainText`
- [ ] **Step 2:** `swift test --filter PastePayloadTests` → FAIL → 구현 → PASS
- [ ] **Step 3: 확인.** `scripts/bundle.sh`를 실행하고, 손쉬운 사용 권한을 허용한 뒤 다음을 확인한다.
  - Ghostty, 브라우저 주소창, Slack, 메모 앱에 ↩로 바로 붙여넣어진다
  - ⇧↩를 누르면 서식 없이 붙여넣어진다
  - ⌘3을 누르면 3번째 항목이 붙여넣어진다
  - 붙여넣은 뒤 원래 앱에 포커스가 있다
  - 붙여넣은 항목이 목록 맨 위로 오고, 중복 항목은 생기지 않는다
  - 다시 빌드해도 권한이 유지된다
- [ ] **Step 4:** 커밋 `feat(app): 현재 앱에 바로 붙여넣기`

### Task 12: 설정 창, 로그인 실행, 보관 정리, MCP 알림 수신

**Files:**
- Create: `Sources/Clipdeck/Settings/SettingsWindowController.swift`, `Sources/Clipdeck/Settings/SettingsView.swift`(탭별 `GeneralTab`, `ShortcutsTab`, `PasteTab`, `HistoryTab`, `PrivacyTab`, `PinboardsTab`, `MCPTab`은 같은 폴더의 개별 파일), `Sources/Clipdeck/Settings/ShortcutRecorder.swift`
- Modify: `Sources/Clipdeck/AppDelegate.swift`

**Interfaces:**
- Consumes: `SettingsStore`, `GlobalHotKey.update`, `purge`, `hideFromMCP`, Pinboard API
- Produces: 탭 내용은 스펙 §6.6과 같다. 연결 동작:
  - 로그인 시 실행: `SMAppService.mainApp.register()`/`unregister()`
  - 보관 기간: 줄이면 확인 창("Pinboard 항목은 지워지지 않습니다")을 띄우고 즉시 `purge`. 앱을 실행할 때와 24시간마다 `purge`
  - MCP에서 숨길 앱 목록에 앱을 추가하면 `hideFromMCP(appBundleID:)`
  - MCP 탭: 실행 파일 절대 경로와 등록 명령(Task 13의 `skillshare mcp add …` 전체 문자열)을 보여 주고, 각각 복사 버튼을 둔다
  - 단축키 녹화기: 패널 열기 키와 패널 내부 키 3개. 다른 패널 키와 겹치면 저장하지 않고 안내한다
  - AppDelegate는 Darwin 알림 `local.hyoloui.clipdeck.db-changed`를 받으면 패널이 열려 있을 때 `PanelModel.reload()`를 호출한다

- [ ] **Step 1: 확인 1.** `scripts/bundle.sh` 후 다음을 확인한다.
  - 메뉴의 "설정…"으로 설정 창이 열린다
  - 단축키를 ⌥⌘V로 바꾸면 즉시 적용되고, ⇧⌘V는 더 이상 반응하지 않는다
  - 보관 기간을 바꾸면 확인 창이 뜬다
  - "로그인 시 실행"이 시스템 설정 > 일반 > 로그인 항목에 나타난다
- [ ] **Step 2: 확인 2.** 패널이 열린 상태에서 `CLIPDECK_DATA_DIR` 없이 Task 8의 printf 방식으로 `tools/call create_text_item {"text":"from-mcp"}`을 보낸다. 패널 목록 맨 위에 `from-mcp`가 바로 나타나야 한다.
- [ ] **Step 3:** 커밋 `feat(app): 설정 창과 MCP 변경 반영`

### Task 13: 세 LLM 등록과 중앙 스킬

**Files:**
- Create: `skill/clipdeck/SKILL.md`(저장소에 원본을 두고 중앙에 설치)
- Create: `scripts/register-mcp.sh`

**Interfaces:**
- Consumes: 설치된 `~/Applications/Clipdeck.app/Contents/MacOS/clipdeck-mcp`
- Produces:
  - `scripts/register-mcp.sh`는 아래를 실행한다. 이미 등록돼 있으면 `skillshare mcp edit clipdeck`으로 같은 값을 맞춘다.

```bash
skillshare mcp add clipdeck --target claude --target codex --target antigravity -- "$HOME/Applications/Clipdeck.app/Contents/MacOS/clipdeck-mcp"
skillshare sync
skillshare mcp check clipdeck --live
```

  - `SKILL.md`: frontmatter `name: clipdeck`, description은 한국어로 "클립보드 기록(Clipdeck)을 MCP로 검색·조회·복사한다. '아까 복사한 거', '클립보드에서 찾아줘', 'Pinboard에 저장해줘' 요청에 사용". 본문에는 다음을 적는다.
    - 도구 8개의 용도
    - 먼저 `search_items`로 찾고 `get_item`으로 전문을 보는 순서
    - 비밀값으로 숨겨진 항목은 MCP에 나오지 않는다는 점
    - 클립보드 내용을 다른 외부 서비스로 보내지 말라는 주의
    - 삭제는 앱에서만 된다는 점

- [ ] **Step 1:** `scripts/register-mcp.sh` 실행. `skillshare mcp check clipdeck --live` 출력에서 claude·codex·antigravity 세 대상이 모두 정상이어야 한다. 실패하면 출력 전문을 사용자에게 보고한다.
- [ ] **Step 2:** `skillshare-managed install ~/Desktop/project/clipdeck/skill/clipdeck` 실행. 이 명령은 차단돼도 exit 0을 반환하므로 결과를 파일로 확인한다. 다음 세 파일이 있어야 한다.
  - `~/.config/skillshare/skills/clipdeck/SKILL.md`
  - `~/.claude/skills/clipdeck/SKILL.md`
  - `~/.gemini/antigravity-cli/skills/clipdeck/SKILL.md`

  보안 검사에서 차단되면 `--force`를 쓰지 말고 사용자에게 보고한다.
- [ ] **Step 3: 확인.** 아래 세 명령 모두 결과에 숨김이 아닌 최근 항목이 나와야 한다.
  - `claude -p "clipdeck MCP의 list_recent로 최근 3개를 보여줘"`
  - `codex exec "clipdeck MCP list_recent limit 3"`
  - agy에서 같은 요청
- [ ] **Step 4:** 커밋 `feat: MCP 중앙 등록 스크립트와 clipdeck 스킬`

### Task 14: 최종 검증

**Files:**
- Create: `docs/verification.md`(결과 기록)

- [ ] **Step 1:** `swift test` → 전체 PASS. 통과한 테스트 수를 기록한다.
- [ ] **Step 2: 성능 측정.** 측정값을 기록한다.

  | 항목 | 측정 방법 | 기준 |
  |---|---|---|
  | 유휴 CPU | `top -l 2 -pid $(pgrep -x Clipdeck) -stats cpu` | 1% 미만 |
  | 메모리 | `footprint Clipdeck` | 80MB 미만 |
  | 패널 표시 시간 | 단축키 → 표시까지 `os_signpost` 로그 또는 체감 | 100ms 이내 |

- [ ] **Step 3: 수동 체크리스트.** 각 항목을 통과·실패로 기록한다.
  - 1Password에서 복사한 비밀번호가 저장되지 않는다
  - 터미널에서 복사한 API 키가 패널에서는 가려져 보이고 MCP에는 나오지 않는다
  - 재부팅하면 자동으로 실행된다
  - 화면 공유 중에는 패널이 상대에게 보이지 않는다
  - 10MB 텍스트를 복사해도 앱이 멈추지 않는다
- [ ] **Step 4:** 커밋 `docs: 최종 검증 기록`. 사용자에게 할 보고:
  - 실패 항목은 원인과 수정 방법을 함께 보고한다
  - 1주 실사용 시작을 안내한다(다른 클립보드 앱은 종료해 둔다)
