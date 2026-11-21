import Foundation

public enum PinboardError: Error, Equatable {
    case emptyName, duplicateName, notFound
}

extension ClipStore {
    /// 새 Pinboard를 만든다. sort는 현재 최댓값 + 1이다.
    public func createPinboard(name: String, color: String?) throws -> Int64 {
        let name = try Self.validName(name)
        return try db.transaction {
            try requireUniqueName(name, excluding: nil)
            let maxSort = try db.query("SELECT COALESCE(MAX(sort), -1) AS m FROM pinboards").first?["m"]
            let next: Int64 = if case .int(let m) = maxSort { m + 1 } else { 0 }
            try db.execute("INSERT INTO pinboards(name, color, sort) VALUES (?, ?, ?)",
                           [.text(name), color.map { .text($0) } ?? .null, .int(next)])
            return db.lastInsertRowID
        }
    }

    public func renamePinboard(id: Int64, name: String) throws {
        let name = try Self.validName(name)
        try db.transaction {
            try requirePinboard(id)
            try requireUniqueName(name, excluding: id)
            try db.execute("UPDATE pinboards SET name = ? WHERE id = ?", [.text(name), .int(id)])
        }
    }

    /// Pinboard만 지운다. 항목 자체는 남는다.
    public func deletePinboard(id: Int64) throws {
        try db.transaction {
            try requirePinboard(id)
            try db.execute("DELETE FROM pinboard_items WHERE pinboard_id = ?", [.int(id)])
            try db.execute("DELETE FROM pinboards WHERE id = ?", [.int(id)])
        }
    }

    public func pinboards() throws -> [Pinboard] {
        try db.query("""
            SELECT p.id, p.name, p.color, p.sort,
                   (SELECT COUNT(*) FROM pinboard_items pi WHERE pi.pinboard_id = p.id) AS item_count
            FROM pinboards p ORDER BY p.sort, p.id
            """).compactMap(Self.pinboard)
    }

    public func pinboard(named name: String) throws -> Pinboard? {
        try db.query("""
            SELECT p.id, p.name, p.color, p.sort,
                   (SELECT COUNT(*) FROM pinboard_items pi WHERE pi.pinboard_id = p.id) AS item_count
            FROM pinboards p WHERE p.name = ?
            """, [.text(name)]).first.flatMap(Self.pinboard)
    }

    /// 이미 들어 있으면 무시한다.
    public func add(itemID: Int64, toPinboard pinboardID: Int64) throws {
        try db.transaction {
            try requirePinboard(pinboardID)
            try db.execute("INSERT OR IGNORE INTO pinboard_items(pinboard_id, item_id) VALUES (?, ?)",
                           [.int(pinboardID), .int(itemID)])
        }
    }

    public func remove(itemID: Int64, fromPinboard pinboardID: Int64) throws {
        try db.transaction {
            try db.execute("DELETE FROM pinboard_items WHERE pinboard_id = ? AND item_id = ?",
                           [.int(pinboardID), .int(itemID)])
        }
    }

    // MARK: 내부

    private static func validName(_ raw: String) throws -> String {
        let name = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if name.isEmpty { throw PinboardError.emptyName }
        return name
    }

    private func requirePinboard(_ id: Int64) throws {
        if try db.query("SELECT 1 AS x FROM pinboards WHERE id = ?", [.int(id)]).isEmpty { throw PinboardError.notFound }
    }

    private func requireUniqueName(_ name: String, excluding id: Int64?) throws {
        let rows = try db.query("SELECT id FROM pinboards WHERE name = ?", [.text(name)])
        if let row = rows.first, case .int(let existing) = row["id"], existing != id { throw PinboardError.duplicateName }
    }

    private static func pinboard(_ row: [String: SQLValue]) -> Pinboard? {
        guard case .int(let id) = row["id"], case .text(let name) = row["name"] else { return nil }
        let color: String? = if case .text(let c) = row["color"] { c } else { nil }
        let sort = if case .int(let s) = row["sort"] { Int(s) } else { 0 }
        let count = if case .int(let n) = row["item_count"] { Int(n) } else { 0 }
        return Pinboard(id: id, name: name, color: color, sort: sort, itemCount: count)
    }
}
