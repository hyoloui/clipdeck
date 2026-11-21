import Testing
import Foundation
@testable import ClipdeckCore

@Suite struct PinboardTests {
    @Test func pinboardCRUD() throws {
        let (store, dir) = try makeTempStore()
        defer { try? FileManager.default.removeItem(at: dir) }
        guard case .inserted(let item) = try store.insert(textClip("a")) else { Issue.record("inserted 아님"); return }

        let first = try store.createPinboard(name: "  업무  ", color: "blue")
        let second = try store.createPinboard(name: "개인", color: nil)
        try store.add(itemID: item, toPinboard: first)
        try store.add(itemID: item, toPinboard: first) // 중복은 무시

        var boards = try store.pinboards()
        #expect(boards.map(\.name) == ["업무", "개인"])
        #expect(boards.map(\.sort) == [0, 1])
        #expect(boards.map(\.itemCount) == [1, 0])
        #expect(boards[0].color == "blue")
        #expect(try store.pinboard(named: "개인")?.id == second)
        #expect(try store.pinboard(named: "없음") == nil)

        try store.renamePinboard(id: first, name: "회사")
        #expect(try store.pinboard(named: "회사")?.id == first)

        try store.remove(itemID: item, fromPinboard: first)
        #expect(try store.pinboards()[0].itemCount == 0)
        try store.add(itemID: item, toPinboard: first)

        try store.deletePinboard(id: first)
        boards = try store.pinboards()
        #expect(boards.map(\.name) == ["개인"])
        #expect(try store.item(id: item) != nil) // 항목 자체는 남음

        #expect(throws: PinboardError.notFound) { try store.deletePinboard(id: 999) }
        #expect(throws: PinboardError.notFound) { try store.renamePinboard(id: 999, name: "x") }
        #expect(throws: PinboardError.notFound) { try store.add(itemID: item, toPinboard: 999) }
    }

    @Test func duplicateNameThrows() throws {
        let (store, dir) = try makeTempStore()
        defer { try? FileManager.default.removeItem(at: dir) }
        let id = try store.createPinboard(name: "A", color: nil)
        _ = try store.createPinboard(name: "B", color: nil)
        #expect(throws: PinboardError.duplicateName) { try store.createPinboard(name: " A ", color: nil) }
        #expect(throws: PinboardError.duplicateName) { try store.renamePinboard(id: id, name: "B") }
        #expect(throws: PinboardError.emptyName) { try store.createPinboard(name: "   ", color: nil) }
        #expect(throws: PinboardError.emptyName) { try store.renamePinboard(id: id, name: "") }
    }
}
