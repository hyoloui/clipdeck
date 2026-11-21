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

/// 커밋 7180b97 시점의 v1 스키마 전체
private let v1Statements = [
    """
    CREATE TABLE IF NOT EXISTS items(
        id INTEGER PRIMARY KEY,
        kind TEXT,
        preview TEXT,
        plain_text TEXT,
        content_hash TEXT UNIQUE,
        source_app_bundle_id TEXT,
        source_app_name TEXT,
        mcp_hidden INTEGER DEFAULT 0,
        created_at REAL,
        last_used_at REAL,
        use_count INTEGER DEFAULT 0
    )
    """,
    """
    CREATE TABLE IF NOT EXISTS item_representations(
        item_id INTEGER REFERENCES items(id) ON DELETE CASCADE,
        uti TEXT,
        data BLOB,
        blob_path TEXT
    )
    """,
    "CREATE INDEX IF NOT EXISTS idx_representations_item ON item_representations(item_id)",
    """
    CREATE TABLE IF NOT EXISTS pinboards(
        id INTEGER PRIMARY KEY,
        name TEXT UNIQUE,
        color TEXT,
        sort INTEGER
    )
    """,
    """
    CREATE TABLE IF NOT EXISTS pinboard_items(
        pinboard_id INTEGER REFERENCES pinboards(id) ON DELETE CASCADE,
        item_id INTEGER REFERENCES items(id) ON DELETE CASCADE,
        PRIMARY KEY(pinboard_id, item_id)
    )
    """,
    "CREATE VIRTUAL TABLE IF NOT EXISTS items_fts USING fts5(plain_text, content='items', content_rowid='id', tokenize='trigram')",
    """
    CREATE TRIGGER IF NOT EXISTS items_ai AFTER INSERT ON items BEGIN
        INSERT INTO items_fts(rowid, plain_text) VALUES (new.id, new.plain_text);
    END
    """,
    """
    CREATE TRIGGER IF NOT EXISTS items_ad AFTER DELETE ON items BEGIN
        INSERT INTO items_fts(items_fts, rowid, plain_text) VALUES ('delete', old.id, old.plain_text);
    END
    """,
    """
    CREATE TRIGGER IF NOT EXISTS items_au AFTER UPDATE ON items BEGIN
        INSERT INTO items_fts(items_fts, rowid, plain_text) VALUES ('delete', old.id, old.plain_text);
        INSERT INTO items_fts(rowid, plain_text) VALUES (new.id, new.plain_text);
    END
    """,
]

@Test func migratesV1ToV2() throws {
    let dir = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: dir) }
    let db = try Database(path: dir.appending(path: "t.sqlite").path)
    for sql in v1Statements { try db.execute(sql) }
    try db.execute("INSERT INTO items(id, kind, preview, plain_text, content_hash) VALUES (1, 'text', 'alpha note', 'alpha note', 'h1')")
    try db.execute("INSERT INTO items(id, kind, preview, plain_text, content_hash) VALUES (2, 'text', 'beta memo', 'beta memo', 'h2')")
    try db.execute("PRAGMA user_version = 1")
    try Schema.migrate(db)
    try Schema.migrate(db) // 두 번 실행해도 안전
    #expect(try db.query("PRAGMA user_version").first?["user_version"] == .int(2))
    #expect(try db.query("SELECT value FROM meta WHERE key = 'next_item_id'").first?["value"] == .int(3))
    let rows = try db.query("SELECT id, plain_text FROM items ORDER BY id")
    #expect(rows.count == 2)
    #expect(rows[0]["plain_text"] == .text("alpha note"))
    #expect(rows[1]["plain_text"] == .text("beta memo"))
    // 기존 행이 FTS에 그대로 있고, 기존 트리거(삽입·삭제)도 계속 동작한다.
    #expect(try db.query("SELECT rowid FROM items_fts WHERE items_fts MATCH 'alpha'").count == 1)
    try db.execute("INSERT INTO items(id, kind, preview, plain_text, content_hash) VALUES (3, 'text', 'gamma words', 'gamma words', 'h3')")
    let hit = try db.query("SELECT rowid FROM items_fts WHERE items_fts MATCH 'gamma'")
    #expect(hit.count == 1)
    try db.execute("DELETE FROM items WHERE id = 3")
    #expect(try db.query("SELECT rowid FROM items_fts WHERE items_fts MATCH 'gamma'").isEmpty)
}

private func indexNames(_ db: Database) throws -> Set<String> {
    Set(try db.query("SELECT name FROM sqlite_master WHERE type = 'index'").compactMap {
        if case .text(let s) = $0["name"] { s } else { nil }
    })
}

private let itemIndexes: Set<String> = ["idx_items_last_used", "idx_items_source_app"]

@Test func migrateCreatesItemIndexes() throws {
    let dir = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: dir) }
    let db = try Database(path: dir.appending(path: "t.sqlite").path)
    try Schema.migrate(db)
    #expect(try indexNames(db).isSuperset(of: itemIndexes))
}

@Test func migrateV1AddsItemIndexes() throws {
    let dir = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: dir) }
    let db = try Database(path: dir.appending(path: "t.sqlite").path)
    for sql in v1Statements { try db.execute(sql) }
    try db.execute("PRAGMA user_version = 1")
    #expect(try indexNames(db).isDisjoint(with: itemIndexes))
    try Schema.migrate(db)
    #expect(try indexNames(db).isSuperset(of: itemIndexes))
}

/// 인덱스 없이 이미 v2로 올라간 DB(개발 중 임시 DB)도 migrate에서 인덱스를 갖춘다
@Test func migrateV2WithoutIndexesAddsThem() throws {
    let dir = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: dir) }
    let db = try Database(path: dir.appending(path: "t.sqlite").path)
    for sql in v1Statements { try db.execute(sql) }
    try db.execute("CREATE TABLE IF NOT EXISTS meta(key TEXT PRIMARY KEY, value INTEGER)")
    try db.execute("INSERT INTO meta(key, value) VALUES ('next_item_id', 1)")
    try db.execute("PRAGMA user_version = 2")
    #expect(try indexNames(db).isDisjoint(with: itemIndexes))
    try Schema.migrate(db)
    #expect(try indexNames(db).isSuperset(of: itemIndexes))
    #expect(try db.query("PRAGMA user_version").first?["user_version"] == .int(2))
}
