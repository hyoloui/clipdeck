import Testing
import Foundation
@testable import ClipdeckCore

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
