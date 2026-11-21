import Foundation
import Testing
@testable import ClipdeckCore

private func makeDB() throws -> Database {
    let dir = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    return try Database(path: dir.appending(path: "t.db").path)
}

@Test func textWithNULRoundTrips() throws {
    let db = try makeDB()
    try db.execute("CREATE TABLE t(s TEXT)")
    try db.execute("INSERT INTO t(s) VALUES (?)", [.text("ab\u{0}cd")])
    let rows = try db.query("SELECT s FROM t")
    guard case .text(let s)? = rows.first?["s"] else { Issue.record("텍스트 없음"); return }
    #expect(s == "ab\u{0}cd")
    #expect(s.count == 5)
}

@Test func concurrentTransactionsOnSameInstance() throws {
    let db = try makeDB()
    try db.execute("CREATE TABLE t(id INTEGER PRIMARY KEY, v INTEGER)")
    let ids = LockedBox<[Int64]>([])
    let errors = LockedBox<[String]>([])
    DispatchQueue.concurrentPerform(iterations: 8) { worker in
        for n in 0..<50 {
            do {
                let id = try db.transaction { () throws -> Int64 in
                    try db.execute("INSERT INTO t(v) VALUES (?)", [.int(Int64(worker * 100 + n))])
                    return db.lastInsertRowID
                }
                ids.mutate { $0.append(id) }
            } catch {
                errors.mutate { $0.append("\(error)") }
            }
        }
    }
    #expect(errors.value.isEmpty)
    let count = try db.query("SELECT COUNT(*) AS c FROM t")
    #expect(count.first?["c"] == .int(400))
    #expect(Set(ids.value).count == 400)
}

private final class LockedBox<T>: @unchecked Sendable {
    private let lock = NSLock()
    private var stored: T
    init(_ value: T) { stored = value }
    var value: T { lock.lock(); defer { lock.unlock() }; return stored }
    func mutate(_ f: (inout T) -> Void) { lock.lock(); f(&stored); lock.unlock() }
}
