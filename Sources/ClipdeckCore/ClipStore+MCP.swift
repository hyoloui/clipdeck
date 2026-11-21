import CryptoKit
import Foundation

/// MCP 도구가 쓰는 조회는 전부 이 파일에만 둔다. `mcp_hidden = 1` 항목은 어느 함수에서도 나오지 않는다.
/// MCP 계층(ToolRegistry)은 `search`·`item`·`pinboards`·`representations`·`plainText`를 직접 부르지 않고
/// 아래 `mcp…` 함수만 쓴다.
extension ClipStore {
    public func mcpSearch(_ q: SearchQuery) throws -> [ClipItem] {
        let (sql, params) = searchSQL(q, extraWhere: "items.mcp_hidden = 0")
        return try db.query(sql, params).compactMap(Self.clipItem)
    }

    /// 숨김 항목과 없는 항목은 둘 다 nil이라 호출부가 구별할 수 없다.
    public func mcpItem(id: Int64) throws -> ClipItem? {
        guard let item = try item(id: id), !item.mcpHidden else { return nil }
        return item
    }

    /// 항목 수는 보이는 항목만 센다.
    public func mcpPinboards() throws -> [Pinboard] {
        var counts: [Int64: Int] = [:]
        for row in try db.query("""
            SELECT pi.pinboard_id AS pid, COUNT(*) AS n FROM pinboard_items pi
            JOIN items ON items.id = pi.item_id WHERE items.mcp_hidden = 0 GROUP BY pi.pinboard_id
            """) {
            if case .int(let pid) = row["pid"], case .int(let n) = row["n"] { counts[pid] = Int(n) }
        }
        return try pinboards().map { board in
            var b = board
            b.itemCount = counts[board.id] ?? 0
            return b
        }
    }

    /// 숨김 확인과 읽기를 한 트랜잭션으로 한다.
    public func mcpRepresentations(itemID: Int64) throws -> [Representation]? {
        try db.transaction {
            guard try mcpItem(id: itemID) != nil else { return nil }
            return try representations(itemID: itemID)
        }
    }

    public func mcpPlainText(itemID: Int64) throws -> String? {
        let rows = try db.query("SELECT plain_text FROM items WHERE id = ? AND mcp_hidden = 0", [.int(itemID)])
        guard let row = rows.first else { return nil }
        if case .text(let s) = row["plain_text"] { return s }
        return nil
    }

    /// 보이는 항목의 사용 기록만 갱신한다(숨김·없는 항목이면 아무것도 하지 않는다).
    public func mcpMarkUsed(id: Int64) throws {
        try db.transaction {
            try db.execute("UPDATE items SET last_used_at = ?, use_count = use_count + 1 WHERE id = ? AND mcp_hidden = 0",
                           [.double(Date.now.timeIntervalSince1970), .int(id)])
        }
    }

    public enum MCPCreateResult: Equatable, Sendable {
        case created(id: Int64)
        /// 탐지기가 비밀값으로 판정해 저장은 했지만 MCP에서는 숨겼다.
        case hidden
        case rejected
        /// 최근 1시간 생성 상한(200개)에 걸렸다. 텍스트 내용과 무관하게 같은 결과다.
        case rateLimited
    }

    static let mcpSourceBundleID = "local.hyoloui.clipdeck.mcp"
    static let mcpCreateLimit = 200

    /// MCP가 만든 텍스트 항목을 저장한다. 호출마다 새 행을 만들고(hash에 UUID를 섞어 중복 제거를 하지 않는다),
    /// 캡처된 행도 이전에 MCP가 만든 행도(사용자가 숨겼을 수 있다) 절대 건드리지 않는다. 응답은 호출자 텍스트의 탐지기 판정으로만 정해지므로,
    /// 저장소에 같은 내용의 숨김 항목이 있는지 알아낼 수 없다.
    public func mcpCreateText(_ text: String, now: Date = .now) throws -> MCPCreateResult {
        guard var clip = ClipBuilder.make(
            representations: [Representation(uti: PasteboardTypes.plainText, data: Data(text.utf8))],
            sourceAppBundleID: Self.mcpSourceBundleID, sourceAppName: "MCP",
            policy: CapturePolicy(detectSecrets: true)) else { return .rejected }
        clip.contentHash = SHA256.hash(data: Data(("mcp\u{0}" + UUID().uuidString + "\u{0}" + text).utf8)).map { String(format: "%02x", $0) }.joined()
        return try db.transaction {
            // 상한 검사는 숨김 행까지 센다. 쓰기 잠금 안에서 해서 동시 호출에도 뚫리지 않는다.
            let since = now.timeIntervalSince1970 - 3600
            if case .int(let n)? = try db.query("SELECT COUNT(*) AS n FROM items WHERE source_app_bundle_id = ? AND created_at > ?",
                                                [.text(Self.mcpSourceBundleID), .double(since)]).first?["n"],
               n >= Int64(Self.mcpCreateLimit) { return .rateLimited }
            let id: Int64 = switch try insertInTransaction(clip, now: now) {
            case .inserted(let id), .bumped(let id): id
            }
            return clip.mcpHidden ? .hidden : .created(id: id)
        }
    }
}
