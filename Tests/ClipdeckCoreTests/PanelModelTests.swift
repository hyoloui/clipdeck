import Testing
import Foundation
@testable import ClipdeckCore

@MainActor
@Suite struct PanelModelTests {
    /// 항목 n개를 시간 순서대로 넣는다(마지막에 넣은 것이 맨 위).
    private func seeded(_ names: [String]) throws -> (ClipStore, PanelModel, [Int64], URL) {
        let (store, dir) = try makeTempStore()
        var ids: [Int64] = []
        for (i, n) in names.enumerated() {
            guard case .inserted(let id) = try store.insert(textClip(n), now: Date(timeIntervalSince1970: 1000 + Double(i))) else {
                Issue.record("inserted 아님"); continue
            }
            ids.append(id)
        }
        let model = PanelModel(store: store)
        model.reload()
        return (store, model, ids, dir)
    }

    @Test func selectionClamps() throws {
        let (_, model, _, dir) = try seeded(["a", "b", "c"])
        defer { try? FileManager.default.removeItem(at: dir) }
        model.moveSelection(-1)
        #expect(model.selectedIndex == 0)
        model.moveSelection(10)
        #expect(model.selectedIndex == 2)
        model.moveSelection(1)
        #expect(model.selectedIndex == 2)
        model.moveSelection(-1)
        #expect(model.selectedIndex == 1)
    }

    @Test func queryResetsSelection() throws {
        let (_, model, _, dir) = try seeded(["apple 1", "apple 2", "apple 3"])
        defer { try? FileManager.default.removeItem(at: dir) }
        model.moveSelection(2)
        #expect(model.selectedIndex == 2)
        model.query = "apple"
        #expect(model.selectedIndex == 0)
        #expect(model.items.count == 3)
        model.query = "apple 2"
        #expect(model.items.map(\.preview) == ["apple 2"])
    }

    @Test func boardCycling() throws {
        let (store, model, _, dir) = try seeded(["a"])
        defer { try? FileManager.default.removeItem(at: dir) }
        _ = try store.createPinboard(name: "업무", color: nil)
        _ = try store.createPinboard(name: "개인", color: nil)
        model.reload()
        #expect(model.boardIndex == 0)
        model.selectNextBoard(); #expect(model.boardIndex == 1)
        model.selectNextBoard(); #expect(model.boardIndex == 2)
        model.selectNextBoard(); #expect(model.boardIndex == 0)
        model.selectPreviousBoard(); #expect(model.boardIndex == 2)
        model.selectBoard(1); #expect(model.boardIndex == 1)
        model.selectBoard(9); #expect(model.boardIndex == 1) // 범위 밖은 무시
    }

    @Test func shortcutIndex() throws {
        let (_, model, ids, dir) = try seeded(Array(repeating: 0, count: 12).enumerated().map { "item \($0.offset)" })
        defer { try? FileManager.default.removeItem(at: dir) }
        #expect(model.item(atShortcut: 1)?.id == ids.last) // 맨 위 = 가장 최근
        #expect(model.item(atShortcut: 9) != nil)
        #expect(model.item(atShortcut: 10) == nil)
        #expect(model.item(atShortcut: 0) == nil)

        let (_, small, _, dir2) = try seeded(["only"])
        defer { try? FileManager.default.removeItem(at: dir2) }
        #expect(small.item(atShortcut: 2) == nil)
    }

    @Test func boardFiltersItems() throws {
        let (store, model, ids, dir) = try seeded(["a", "b", "c"])
        defer { try? FileManager.default.removeItem(at: dir) }
        let board = try store.createPinboard(name: "업무", color: nil)
        try store.add(itemID: ids[1], toPinboard: board)
        model.reload()
        #expect(model.items.count == 3)
        model.selectNextBoard()
        #expect(model.items.map(\.id) == [ids[1]])
        model.selectNextBoard()
        #expect(model.items.count == 3)
    }

    @Test func displaysAtMost200() throws {
        let (store, dir) = try makeTempStore()
        defer { try? FileManager.default.removeItem(at: dir) }
        for i in 0..<230 { _ = try store.insert(textClip("n\(i)"), now: Date(timeIntervalSince1970: Double(i))) }
        let model = PanelModel(store: store)
        model.reload()
        #expect(model.items.count == 200)
    }

    @Test func kindAndAppFilters() throws {
        let (store, dir) = try makeTempStore()
        defer { try? FileManager.default.removeItem(at: dir) }
        _ = try store.insert(textClip("alpha", app: "com.a"), now: Date(timeIntervalSince1970: 1))
        _ = try store.insert(textClip("beta", app: "com.b"), now: Date(timeIntervalSince1970: 2))
        let link = NewClip(kind: .link, preview: "https://x.dev", plainText: "https://x.dev", contentHash: "h-link",
                           sourceAppBundleID: "com.a", sourceAppName: "com.a", mcpHidden: false,
                           representations: [Representation(uti: "public.utf8-plain-text", data: Data("https://x.dev".utf8))])
        _ = try store.insert(link, now: Date(timeIntervalSince1970: 3))
        let model = PanelModel(store: store)
        model.reload()
        #expect(model.items.count == 3)
        model.kindFilter = .link
        #expect(model.items.map(\.preview) == ["https://x.dev"])
        model.kindFilter = nil
        model.appFilter = "com.a"
        #expect(model.items.count == 2)
        model.kindFilter = .text
        #expect(model.items.map(\.preview) == ["alpha"]) // 조합
        // 열 때 초기화
        model.query = "zzz"
        model.resetForShow()
        #expect(model.kindFilter == nil && model.appFilter == nil && model.query.isEmpty)
        #expect(model.items.count == 3)
    }

    /// 검색어가 비워진 시각을 기억하고, 패널을 열 때의 초기화는 세지 않는다
    @Test func queryClearedAtTracksClearing() throws {
        let (_, model, _, dir) = try seeded(["a"])
        defer { try? FileManager.default.removeItem(at: dir) }
        #expect(model.queryClearedAt == nil)
        model.query = "ab"
        #expect(model.queryClearedAt == nil)
        model.query = ""
        let cleared = try #require(model.queryClearedAt)
        #expect(Date().timeIntervalSince(cleared) < 1)
        model.query = "x"
        model.resetForShow()
        #expect(model.queryClearedAt == nil)
    }

    @Test func loadErrorOnFailure() throws {
        let (store, dir) = try makeTempStore()
        defer { try? FileManager.default.removeItem(at: dir) }
        _ = try store.insert(textClip("a"))
        let model = PanelModel(store: store)
        model.reload()
        #expect(model.loadError == nil)
        #expect(model.items.count == 1)
        try store.db.execute("DROP TABLE pinboards") // 읽기 실패를 만든다
        model.reload()
        #expect(model.loadError != nil)
        #expect(model.items.isEmpty)
    }
}
