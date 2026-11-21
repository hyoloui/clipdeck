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

    public func mcpRepresentations(itemID: Int64) throws -> [Representation]? {
        guard try mcpItem(id: itemID) != nil else { return nil }
        return try representations(itemID: itemID)
    }

    public func mcpPlainText(itemID: Int64) throws -> String? {
        guard try mcpItem(id: itemID) != nil else { return nil }
        return try plainText(itemID: itemID)
    }

    /// 저장하고, 결과 항목이 MCP에 보이면 id를, 숨김이면 nil을 돌려준다(이미 숨겨진 항목과 내용이 같을 때도 nil).
    public func mcpInsert(_ clip: NewClip) throws -> Int64? {
        let id: Int64 = switch try insert(clip) {
        case .inserted(let id), .bumped(let id): id
        }
        return try mcpItem(id: id)?.id
    }
}
