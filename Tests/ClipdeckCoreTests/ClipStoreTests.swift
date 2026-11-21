import Testing
import Foundation
import CryptoKit
@testable import ClipdeckCore

@Test func insertThenReadBack() throws {
    let (store, dir) = try makeTempStore()
    defer { try? FileManager.default.removeItem(at: dir) }
    let result = try store.insert(textClip("안녕", app: "com.apple.Notes"))
    guard case .inserted(let id) = result else { Issue.record("inserted 아님"); return }
    let item = try #require(try store.item(id: id))
    #expect(item.kind == .text)
    #expect(item.preview == "안녕")
    #expect(item.sourceAppBundleID == "com.apple.Notes")
    #expect(try store.plainText(itemID: id) == "안녕")
    #expect(try store.representations(itemID: id).count == 1)
}

@Test func duplicateHashBumps() throws {
    let (store, dir) = try makeTempStore()
    defer { try? FileManager.default.removeItem(at: dir) }
    let t0 = Date(timeIntervalSince1970: 1_000)
    let t1 = Date(timeIntervalSince1970: 2_000)
    guard case .inserted(let id) = try store.insert(textClip("a"), now: t0) else { Issue.record("inserted 아님"); return }
    #expect(try store.insert(textClip("a"), now: t1) == .bumped(id))
    let item = try #require(try store.item(id: id))
    #expect(item.lastUsedAt == t1)
    #expect(item.createdAt == t0)
    #expect(try store.db.query("SELECT COUNT(*) AS n FROM items").first?["n"] == .int(1))
}

private func blobClip(_ data: Data) -> NewClip {
    NewClip(kind: .image, preview: "img", plainText: nil, contentHash: "big-" + String(data.count),
            sourceAppBundleID: nil, sourceAppName: nil, mcpHidden: false,
            representations: [Representation(uti: "public.png", data: data)])
}

private func sha256Hex(_ data: Data) -> String {
    SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
}

@Test func largeRepresentationGoesToBlob() throws {
    let (store, dir) = try makeTempStore()
    defer { try? FileManager.default.removeItem(at: dir) }
    let data = Data((0..<10_000_000).map { UInt8(truncatingIfNeeded: $0 &* 31) })
    guard case .inserted(let id) = try store.insert(blobClip(data)) else { Issue.record("inserted 아님"); return }
    let rows = try store.db.query("SELECT data, blob_path FROM item_representations WHERE item_id = ?", [.int(id)])
    #expect(rows.first?["data"] == .null)
    #expect(FileManager.default.fileExists(atPath: dir.appending(path: "blobs/" + sha256Hex(data)).path))
    #expect(try store.representations(itemID: id).first?.data == data)
}

@Test func smallRepresentationStaysInline() throws {
    let (store, dir) = try makeTempStore()
    defer { try? FileManager.default.removeItem(at: dir) }
    _ = try store.insert(textClip("작은 것"))
    let blobs = dir.appending(path: "blobs").path
    let files = (try? FileManager.default.contentsOfDirectory(atPath: blobs)) ?? []
    #expect(files.isEmpty)
}

@Test func eraseHistoryKeepsPinboardItems() throws {
    let (store, dir) = try makeTempStore()
    defer { try? FileManager.default.removeItem(at: dir) }
    guard case .inserted(let keep) = try store.insert(textClip("keep")),
          case .inserted(let drop) = try store.insert(textClip("drop")) else { Issue.record("inserted 아님"); return }
    try store.db.execute("INSERT INTO pinboards(id, name, sort) VALUES (1, 'p', 0)")
    try store.db.execute("INSERT INTO pinboard_items(pinboard_id, item_id) VALUES (1, ?)", [.int(keep)])
    try store.eraseHistory()
    #expect(try store.item(id: keep) != nil)
    #expect(try store.item(id: drop) == nil)
}

@Test func deleteRemovesBlob() throws {
    let (store, dir) = try makeTempStore()
    defer { try? FileManager.default.removeItem(at: dir) }
    let data = Data(repeating: 7, count: 100_000)
    guard case .inserted(let id) = try store.insert(blobClip(data)) else { Issue.record("inserted 아님"); return }
    let file = dir.appending(path: "blobs/" + sha256Hex(data))
    #expect(FileManager.default.fileExists(atPath: file.path))
    try store.delete(id: id)
    #expect(!FileManager.default.fileExists(atPath: file.path))
    #expect(try store.item(id: id) == nil)
}

@Test func sharedBlobSurvivesUntilLastReference() throws {
    let (store, dir) = try makeTempStore()
    defer { try? FileManager.default.removeItem(at: dir) }
    let data = Data(repeating: 9, count: 100_000)
    var a = blobClip(data); a.contentHash = "a"
    var b = blobClip(data); b.contentHash = "b"
    guard case .inserted(let ida) = try store.insert(a), case .inserted(let idb) = try store.insert(b) else { Issue.record("inserted 아님"); return }
    let file = dir.appending(path: "blobs/" + sha256Hex(data))
    try store.delete(id: ida)
    #expect(FileManager.default.fileExists(atPath: file.path))
    try store.delete(id: idb)
    #expect(!FileManager.default.fileExists(atPath: file.path))
}

@Test func hideFromMCPMarksExistingItems() throws {
    let (store, dir) = try makeTempStore()
    defer { try? FileManager.default.removeItem(at: dir) }
    guard case .inserted(let a) = try store.insert(textClip("1", app: "x.app")),
          case .inserted(let b) = try store.insert(textClip("2", app: "x.app")),
          case .inserted(let c) = try store.insert(textClip("3", app: "y.app")) else { Issue.record("inserted 아님"); return }
    try store.hideFromMCP(appBundleID: "x.app")
    #expect(try store.item(id: a)?.mcpHidden == true)
    #expect(try store.item(id: b)?.mcpHidden == true)
    #expect(try store.item(id: c)?.mcpHidden == false)
    try store.setMCPHidden(id: a, false)
    #expect(try store.item(id: a)?.mcpHidden == false)
}

@Test func markUsedUpdatesCounters() throws {
    let (store, dir) = try makeTempStore()
    defer { try? FileManager.default.removeItem(at: dir) }
    guard case .inserted(let id) = try store.insert(textClip("u"), now: Date(timeIntervalSince1970: 1)) else { Issue.record("inserted 아님"); return }
    try store.markUsed(id: id, now: Date(timeIntervalSince1970: 5))
    let item = try #require(try store.item(id: id))
    #expect(item.lastUsedAt == Date(timeIntervalSince1970: 5))
    #expect(item.useCount == 1)
}

@Test func concurrentReaderDoesNotLock() async throws {
    let (writer, dir) = try makeTempStore()
    defer { try? FileManager.default.removeItem(at: dir) }
    let reader = try ClipStore(directory: dir)
    let w = Task.detached { for i in 0..<200 { _ = try writer.insert(textClip("w\(i)")) } }
    let r = Task.detached { for _ in 0..<200 { _ = try reader.item(id: 1) } }
    try await w.value
    try await r.value
}

@Test func bumpNeverUnhides() throws {
    let (store, dir) = try makeTempStore()
    defer { try? FileManager.default.removeItem(at: dir) }
    guard case .inserted(let a) = try store.insert(textClip("a")) else { Issue.record("inserted 아님"); return }
    #expect(try store.insert(textClip("a", hidden: true)) == .bumped(a))
    #expect(try store.item(id: a)?.mcpHidden == true)
    guard case .inserted(let b) = try store.insert(textClip("b", hidden: true)) else { Issue.record("inserted 아님"); return }
    #expect(try store.insert(textClip("b")) == .bumped(b))
    #expect(try store.item(id: b)?.mcpHidden == true)
}

@Test func missingBlobThrows() throws {
    let (store, dir) = try makeTempStore()
    defer { try? FileManager.default.removeItem(at: dir) }
    let data = Data(repeating: 3, count: 100_000)
    guard case .inserted(let id) = try store.insert(blobClip(data)) else { Issue.record("inserted 아님"); return }
    try FileManager.default.removeItem(at: dir.appending(path: "blobs/" + sha256Hex(data)))
    #expect(throws: (any Error).self) { try store.representations(itemID: id) }
}

@Test func blobThresholdBoundary() throws {
    let (store, dir) = try makeTempStore()
    defer { try? FileManager.default.removeItem(at: dir) }
    var inline = blobClip(Data(repeating: 1, count: 65_536)); inline.contentHash = "inline"
    var big = blobClip(Data(repeating: 2, count: 65_537)); big.contentHash = "big"
    guard case .inserted(let a) = try store.insert(inline), case .inserted(let b) = try store.insert(big) else { Issue.record("inserted 아님"); return }
    #expect(try store.db.query("SELECT blob_path FROM item_representations WHERE item_id = ?", [.int(a)]).first?["blob_path"] == .null)
    #expect(try store.db.query("SELECT blob_path FROM item_representations WHERE item_id = ?", [.int(b)]).first?["blob_path"] != .null)
}

@Test func idsAreNeverReused() throws {
    let (store, dir) = try makeTempStore()
    defer { try? FileManager.default.removeItem(at: dir) }
    var ids: [Int64] = []
    for s in ["one", "two", "three"] {
        if case .inserted(let id) = try store.insert(textClip(s)) { ids.append(id) }
    }
    #expect(ids == [1, 2, 3])
    try store.delete(id: 3)
    guard case .inserted(let next) = try store.insert(textClip("four")) else { Issue.record("삽입 실패"); return }
    #expect(next == 4)
}

@Test func counterCorrectsToMaxIdPlusOne() throws {
    let (store, dir) = try makeTempStore()
    defer { try? FileManager.default.removeItem(at: dir) }
    // 외부에서 카운터 밖으로 행을 직접 넣은 경우
    try store.db.execute("INSERT INTO items(id, kind, preview, plain_text, content_hash) VALUES (50, 'text', 'x', 'x', 'hx')")
    guard case .inserted(let next) = try store.insert(textClip("after")) else { Issue.record("삽입 실패"); return }
    #expect(next == 51)
}

@Test func mcpMarkUsedIgnoresHidden() throws {
    let (store, dir) = try makeTempStore()
    defer { try? FileManager.default.removeItem(at: dir) }
    guard case .inserted(let hid) = try store.insert(textClip("secret-ish", hidden: true)),
          case .inserted(let vis) = try store.insert(textClip("visible")) else { return }
    try store.mcpMarkUsed(id: hid)
    try store.mcpMarkUsed(id: vis)
    #expect(try store.item(id: hid)?.useCount == 0)
    #expect(try store.item(id: vis)?.useCount == 1)
}

@Test func createTextRateLimited() throws {
    let (store, dir) = try makeTempStore()
    defer { try? FileManager.default.removeItem(at: dir) }
    let now = Date(timeIntervalSince1970: 1_800_000_000)
    for i in 0..<200 {
        guard case .created = try store.mcpCreateText("메모 번호 \(i)", now: now) else { Issue.record("\(i)번째 실패"); return }
    }
    #expect(try store.mcpCreateText("한 개 더 있는 메모", now: now) == .rateLimited)
    // 비밀값이어도 같은 응답
    #expect(try store.mcpCreateText("sk-" + String(repeating: "aB3dE6gH9j", count: 4), now: now) == .rateLimited)
    #expect(try store.db.query("SELECT COUNT(*) AS n FROM items").first?["n"] == .int(200))
    #expect(try store.mcpCreateText("한 개 더 있는 메모", now: now.addingTimeInterval(3601)) != .rateLimited)
}
