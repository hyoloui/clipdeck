import Testing
import Foundation
@testable import ClipdeckCore

@Test func migrateCreatesSchemaInWALMode() throws {
    let dir = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    let db = try Database(path: dir.appending(path: "t.sqlite").path)
    try Schema.migrate(db)
    #expect(try db.query("PRAGMA user_version").first?["user_version"] == .int(2))
    #expect(try db.query("PRAGMA journal_mode").first?["journal_mode"] == .text("wal"))
    let names = try db.query("SELECT name FROM sqlite_master").compactMap { if case .text(let s) = $0["name"] { s } else { nil } }
    for t in ["items", "item_representations", "pinboards", "pinboard_items", "items_fts", "meta"] { #expect(names.contains(t)) }
    try Schema.migrate(db) // 두 번 실행해도 오류 없음
}

@Test func migratesV1ToV2() throws {
    let dir = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    let db = try Database(path: dir.appending(path: "t.sqlite").path)
    // v1 스키마를 직접 만든다(meta 없음).
    try db.execute("""
        CREATE TABLE items(id INTEGER PRIMARY KEY, kind TEXT, preview TEXT, plain_text TEXT, content_hash TEXT UNIQUE,
            source_app_bundle_id TEXT, source_app_name TEXT, mcp_hidden INTEGER DEFAULT 0,
            created_at REAL, last_used_at REAL, use_count INTEGER DEFAULT 0)
        """)
    try db.execute("INSERT INTO items(id, kind, preview, plain_text, content_hash) VALUES (1, 'text', 'a', 'a', 'h1')")
    try db.execute("INSERT INTO items(id, kind, preview, plain_text, content_hash) VALUES (2, 'text', 'b', 'b', 'h2')")
    try db.execute("PRAGMA user_version = 1")
    try Schema.migrate(db)
    try Schema.migrate(db) // 두 번 실행해도 안전
    #expect(try db.query("PRAGMA user_version").first?["user_version"] == .int(2))
    #expect(try db.query("SELECT value FROM meta WHERE key = 'next_item_id'").first?["value"] == .int(3))
    #expect(try db.query("SELECT COUNT(*) AS n FROM items").first?["n"] == .int(2))
}
