import Foundation
import CryptoKit

/// 클립보드 항목 저장소. 앱과 MCP 서버가 같은 폴더를 열어 공유한다.
public final class ClipStore: @unchecked Sendable {
    /// 이후 작업의 extension 파일에서 쓴다.
    let db: Database
    let directory: URL
    var blobsDirectory: URL { directory.appending(path: "blobs", directoryHint: .isDirectory) }

    /// 이 크기를 넘는 표현 데이터는 파일(blobs/<sha256>)로 뺀다.
    static let blobThreshold = 64 * 1024

    public init(directory: URL) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        self.directory = directory
        db = try Database(path: directory.appending(path: "clipdeck.sqlite").path)
        try Schema.migrate(db)
    }

    public static func defaultDirectory() -> URL {
        if let path = ProcessInfo.processInfo.environment["CLIPDECK_DATA_DIR"], !path.isEmpty {
            return URL(fileURLWithPath: path, isDirectory: true)
        }
        return FileManager.default.homeDirectoryForCurrentUser
            .appending(path: "Library/Application Support/Clipdeck", directoryHint: .isDirectory)
    }

    // MARK: 쓰기

    public func insert(_ clip: NewClip, now: Date = .now) throws -> InsertResult {
        try db.transaction {
            let ts = now.timeIntervalSince1970
            if let row = try db.query("SELECT id FROM items WHERE content_hash = ?", [.text(clip.contentHash)]).first,
               case .int(let id) = row["id"] {
                // 한번 숨겨진 항목은 bump로 풀리지 않는다.
                try db.execute("UPDATE items SET last_used_at = ?, use_count = use_count + 1, mcp_hidden = max(mcp_hidden, ?) WHERE id = ?",
                               [.double(ts), .int(clip.mcpHidden ? 1 : 0), .int(id)])
                return .bumped(id)
            }
            try db.execute("""
                INSERT INTO items(kind, preview, plain_text, content_hash, source_app_bundle_id, source_app_name,
                                  mcp_hidden, created_at, last_used_at, use_count)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, 0)
                """, [
                .text(clip.kind.rawValue), .text(clip.preview), clip.plainText.map { .text($0) } ?? .null,
                .text(clip.contentHash), clip.sourceAppBundleID.map { .text($0) } ?? .null,
                clip.sourceAppName.map { .text($0) } ?? .null, .int(clip.mcpHidden ? 1 : 0), .double(ts), .double(ts),
            ])
            let id = db.lastInsertRowID
            for rep in clip.representations {
                if rep.data.count > Self.blobThreshold {
                    let path = try writeBlob(rep.data)
                    try db.execute("INSERT INTO item_representations(item_id, uti, data, blob_path) VALUES (?, ?, NULL, ?)",
                                   [.int(id), .text(rep.uti), .text(path)])
                } else {
                    try db.execute("INSERT INTO item_representations(item_id, uti, data, blob_path) VALUES (?, ?, ?, NULL)",
                                   [.int(id), .text(rep.uti), .blob(rep.data)])
                }
            }
            return .inserted(id)
        }
    }

    public func markUsed(id: Int64, now: Date = .now) throws {
        try db.transaction {
            try db.execute("UPDATE items SET last_used_at = ?, use_count = use_count + 1 WHERE id = ?",
                           [.double(now.timeIntervalSince1970), .int(id)])
        }
    }

    public func delete(id: Int64) throws {
        try deleteItems(where: "id = ?", params: [.int(id)])
    }

    /// Pinboard에 들어 있지 않은 항목을 모두 지운다.
    public func eraseHistory() throws {
        try deleteItems(where: "NOT EXISTS (SELECT 1 FROM pinboard_items WHERE item_id = items.id)", params: [])
    }

    public func setMCPHidden(id: Int64, _ hidden: Bool) throws {
        try db.transaction {
            try db.execute("UPDATE items SET mcp_hidden = ? WHERE id = ?", [.int(hidden ? 1 : 0), .int(id)])
        }
    }

    public func hideFromMCP(appBundleID: String) throws {
        try db.transaction {
            try db.execute("UPDATE items SET mcp_hidden = 1 WHERE source_app_bundle_id = ?", [.text(appBundleID)])
        }
    }

    /// 조건에 맞는 항목을 지우고, 더는 참조되지 않는 blob 파일도 지운다.
    /// `condition`은 items 테이블에 대한 WHERE 절 내용이다(호출자가 만든 고정 문자열만 쓴다).
    func deleteItems(where condition: String, params: [SQLValue]) throws {
        try db.transaction {
            let paths = try db.query("""
                SELECT DISTINCT blob_path FROM item_representations
                WHERE blob_path IS NOT NULL AND item_id IN (SELECT id FROM items WHERE \(condition))
                """, params).compactMap { row -> String? in
                if case .text(let p) = row["blob_path"] { return p } else { return nil }
            }
            try db.execute("DELETE FROM items WHERE \(condition)", params)
            // 쓰기 잠금을 쥔 채로 확인하므로 다른 프로세스의 insert와 경합하지 않는다.
            for path in paths {
                let rows = try db.query("SELECT 1 AS x FROM item_representations WHERE blob_path = ? LIMIT 1", [.text(path)])
                if rows.isEmpty { try? FileManager.default.removeItem(at: directory.appending(path: path)) }
            }
        }
    }

    // MARK: 읽기

    public func item(id: Int64) throws -> ClipItem? {
        try db.query("""
            SELECT id, kind, preview, content_hash, source_app_bundle_id, source_app_name, mcp_hidden,
                   created_at, last_used_at, use_count FROM items WHERE id = ?
            """, [.int(id)]).first.flatMap(Self.clipItem)
    }

    public func representations(itemID: Int64) throws -> [Representation] {
        try db.query("SELECT uti, data, blob_path FROM item_representations WHERE item_id = ? ORDER BY rowid",
                     [.int(itemID)]).compactMap { row -> Representation? in
            guard case .text(let uti) = row["uti"] else { return nil }
            if case .blob(let data) = row["data"] { return Representation(uti: uti, data: data) }
            if case .text(let path) = row["blob_path"] {
                return Representation(uti: uti, data: try Data(contentsOf: directory.appending(path: path)))
            }
            return nil
        }
    }

    public func plainText(itemID: Int64) throws -> String? {
        if case .text(let s) = try db.query("SELECT plain_text FROM items WHERE id = ?", [.int(itemID)]).first?["plain_text"] { return s }
        return nil
    }

    // MARK: 내부

    /// 데이터를 blobs/<sha256>에 쓰고 directory 기준 상대 경로를 돌려준다.
    private func writeBlob(_ data: Data) throws -> String {
        let name = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        try FileManager.default.createDirectory(at: blobsDirectory, withIntermediateDirectories: true)
        let file = blobsDirectory.appending(path: name)
        if !FileManager.default.fileExists(atPath: file.path) { try data.write(to: file, options: .atomic) }
        return "blobs/" + name
    }

    static func clipItem(_ row: [String: SQLValue]) -> ClipItem? {
        guard case .int(let id) = row["id"], case .text(let kind) = row["kind"], let k = ItemKind(rawValue: kind),
              case .text(let hash) = row["content_hash"] else { return nil }
        func text(_ key: String) -> String? { if case .text(let s) = row[key] { s } else { nil } }
        func double(_ key: String) -> Double { if case .double(let d) = row[key] { d } else { 0 } }
        func int(_ key: String) -> Int { if case .int(let i) = row[key] { Int(i) } else { 0 } }
        return ClipItem(id: id, kind: k, preview: text("preview") ?? "", contentHash: hash,
                        sourceAppBundleID: text("source_app_bundle_id"), sourceAppName: text("source_app_name"),
                        mcpHidden: int("mcp_hidden") != 0,
                        createdAt: Date(timeIntervalSince1970: double("created_at")),
                        lastUsedAt: Date(timeIntervalSince1970: double("last_used_at")), useCount: int("use_count"))
    }
}
