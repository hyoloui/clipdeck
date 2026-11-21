import Foundation

public enum Schema {
    public static let version: Int32 = 2

    /// user_version이 현재 버전보다 낮을 때만 테이블을 만든다.
    public static func migrate(_ db: Database) throws {
        let current = try db.query("PRAGMA user_version").first?["user_version"]
        if case .int(let v) = current, v >= Int64(version) { return }
        try db.transaction {
            for sql in statements { try db.execute(sql) }
            // v2: 항목 id 카운터. 이미 있으면(재실행) 건드리지 않는다.
            try db.execute("INSERT OR IGNORE INTO meta(key, value) SELECT 'next_item_id', COALESCE(MAX(id), 0) + 1 FROM items")
            try db.execute("PRAGMA user_version = \(version)")
        }
    }

    private static let statements = [
        "CREATE TABLE IF NOT EXISTS meta(key TEXT PRIMARY KEY, value INTEGER)",
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
}
