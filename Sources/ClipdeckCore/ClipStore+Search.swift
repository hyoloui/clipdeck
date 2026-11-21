import Foundation

extension ClipStore {
    /// 텍스트가 비어 있으면 최근 사용 순 목록, 아니면 검색 결과를 `last_used_at DESC`로 돌려준다.
    public func search(_ q: SearchQuery) throws -> [ClipItem] {
        let (sql, params) = searchSQL(q, extraWhere: nil)
        return try db.query(sql, params).compactMap(Self.clipItem)
    }

    /// 검색 SQL과 바인딩 값을 만든다. `extraWhere`는 호출부가 주는 고정 SQL 조각이며 AND로 붙는다.
    /// 사용자 입력은 전부 바인딩한다.
    func searchSQL(_ q: SearchQuery, extraWhere: String?) -> (String, [SQLValue]) {
        var conditions: [String] = []
        var params: [SQLValue] = []

        let text = q.text.trimmingCharacters(in: .whitespacesAndNewlines)
        if !text.isEmpty {
            if text.count >= 3 {
                // trigram은 3자 이상에서만 동작한다. 큰따옴표 구문으로 감싸 FTS 연산자를 무력화한다.
                conditions.append("items.id IN (SELECT rowid FROM items_fts WHERE items_fts MATCH ?)")
                params.append(.text("\"" + text.replacingOccurrences(of: "\"", with: "\"\"") + "\""))
            } else {
                let escaped = text.replacingOccurrences(of: "\\", with: "\\\\")
                    .replacingOccurrences(of: "%", with: "\\%")
                    .replacingOccurrences(of: "_", with: "\\_")
                conditions.append("items.plain_text LIKE ? ESCAPE '\\'")
                params.append(.text("%" + escaped + "%"))
            }
        }
        if let kind = q.kind {
            conditions.append("items.kind = ?")
            params.append(.text(kind.rawValue))
        }
        if let app = q.appBundleID {
            conditions.append("items.source_app_bundle_id = ?")
            params.append(.text(app))
        }
        if let board = q.pinboardID {
            conditions.append("EXISTS (SELECT 1 FROM pinboard_items pi WHERE pi.item_id = items.id AND pi.pinboard_id = ?)")
            params.append(.int(board))
        }
        if let since = q.since {
            conditions.append("items.last_used_at >= ?")
            params.append(.double(since.timeIntervalSince1970))
        }
        if let extraWhere, !extraWhere.isEmpty { conditions.append("(" + extraWhere + ")") }

        var sql = """
            SELECT items.id, items.kind, items.preview, items.content_hash, items.source_app_bundle_id,
                   items.source_app_name, items.mcp_hidden, items.created_at, items.last_used_at, items.use_count
            FROM items
            """
        if !conditions.isEmpty { sql += " WHERE " + conditions.joined(separator: " AND ") }
        sql += " ORDER BY items.last_used_at DESC, items.id DESC LIMIT ?"
        params.append(.int(Int64(max(q.limit, 0))))
        return (sql, params)
    }
}
