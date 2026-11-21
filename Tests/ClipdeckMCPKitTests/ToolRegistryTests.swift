import ClipdeckCore
import Foundation
import Testing
@testable import ClipdeckMCPKit

// 테스트용 가짜 키(소스에 통째로 두지 않는다)
private let fakeAPIKey = "sk-ant-" + "api03-q7Lm2Xv9Rt4Kp8Zw3Hd6Ns1Bc5Yf0Ge2Ja9Uo7E"

private func n(_ v: Int64) -> JSONValue { .number(Double(v)) }

@Suite struct ToolRegistryTests {
    @Test func hiddenNeverAppears() throws {
        let (store, dir) = try makeTempStore()
        defer { try? FileManager.default.removeItem(at: dir) }
        let secret = "hunter2-secret-needle-value"
        let hiddenID = try insertText(store, secret, hidden: true)
        let visibleID = try insertText(store, "visible-note-text")
        let board = try store.createPinboard(name: "work", color: nil)
        try store.add(itemID: hiddenID, toPinboard: board)
        try store.add(itemID: visibleID, toPinboard: board)
        let clip = FakeClipboard()
        let reg = makeRegistry(store, clipboard: clip)

        let listings: [ToolResult] = [
            reg.call(name: "search_items", arguments: ["query": .string("needle")]),
            reg.call(name: "search_items", arguments: ["query": .string(""), "pinboard": .string("work")]),
            reg.call(name: "list_recent", arguments: [:]),
            reg.call(name: "list_pinboard_items", arguments: ["pinboard": n(board)]),
        ]
        for r in listings {
            #expect(!r.isError)
            #expect(!ids(r).contains(hiddenID))
            #expect(!text(r).contains(secret))
        }
        #expect(ids(listings[2]) == [visibleID])
        #expect(ids(listings[3]) == [visibleID])

        let get = reg.call(name: "get_item", arguments: ["id": n(hiddenID)])
        let copy = reg.call(name: "copy_to_clipboard", arguments: ["id": n(hiddenID)])
        let pin = reg.call(name: "add_to_pinboard", arguments: ["id": n(hiddenID), "pinboard": .string("work")])
        for r in [get, copy, pin] {
            #expect(r.isError)
            #expect(!text(r).contains(secret))
        }
        #expect(clip.writes.isEmpty)

        let boards = reg.call(name: "list_pinboards", arguments: [:])
        #expect(text(boards).contains("\"item_count\":1"))
        #expect(!text(boards).contains("\"item_count\":2"))
    }

    @Test func hiddenAndMissingErrorsAreIdentical() throws {
        let (store, dir) = try makeTempStore()
        defer { try? FileManager.default.removeItem(at: dir) }
        let hiddenID = try insertText(store, "hidden-one", hidden: true)
        _ = try store.createPinboard(name: "b", color: nil)
        let reg = makeRegistry(store)
        let missing: Int64 = 99_999
        for (tool, extra) in [("get_item", [:]), ("copy_to_clipboard", [:]),
                              ("add_to_pinboard", ["pinboard": JSONValue.string("b")])] as [(String, [String: JSONValue])] {
            let a = reg.call(name: tool, arguments: extra.merging(["id": n(hiddenID)]) { $1 })
            let b = reg.call(name: tool, arguments: extra.merging(["id": n(missing)]) { $1 })
            #expect(a.isError && b.isError)
            #expect(a == b)
        }
    }

    @Test func limitClamped() throws {
        let (store, dir) = try makeTempStore()
        defer { try? FileManager.default.removeItem(at: dir) }
        for i in 0..<120 { try insertText(store, "item number \(i)") }
        let reg = makeRegistry(store)
        #expect(ids(reg.call(name: "list_recent", arguments: ["limit": .number(500)])).count == 100)
        #expect(ids(reg.call(name: "list_recent", arguments: [:])).count == 20)
        #expect(ids(reg.call(name: "search_items", arguments: ["query": .string("item"), "limit": .number(500)])).count == 100)
    }

    @Test func getItemTruncates() throws {
        let (store, dir) = try makeTempStore()
        defer { try? FileManager.default.removeItem(at: dir) }
        let big = String(repeating: "가", count: 50_000) // 150,000바이트
        let id = try insertText(store, big)
        let out = text(makeRegistry(store).call(name: "get_item", arguments: ["id": n(id)]))
        let body = out.components(separatedBy: "\n\n[잘림").first ?? ""
        #expect(out.contains("[잘림"))
        #expect(body.utf8.count <= 100 * 1024)
        #expect(body.utf8.count > 100 * 1024 - 3)
    }

    @Test func getItemImageScaled() throws {
        let (store, dir) = try makeTempStore()
        defer { try? FileManager.default.removeItem(at: dir) }
        let png = makePNG(width: 2048, height: 1024)
        let clip = try #require(ClipBuilder.make(representations: [Representation(uti: PasteboardTypes.png, data: png)],
                                                 sourceAppBundleID: nil, sourceAppName: nil, policy: CapturePolicy()))
        let idopt = try store.mcpInsert(clip)
        let id = try #require(idopt)
        let r = makeRegistry(store).call(name: "get_item", arguments: ["id": n(id)])
        guard case .image(let b64, let mime)? = r.content.first else { Issue.record("이미지 콘텐츠 아님"); return }
        #expect(mime == "image/png")
        let raw = try #require(Data(base64Encoded: b64))
        let size = try #require(pngSize(raw))
        #expect(size.0 == 1024 && size.1 == 512)
    }

    @Test func getItemSmallImageKeptAndFilePaths() throws {
        let (store, dir) = try makeTempStore()
        defer { try? FileManager.default.removeItem(at: dir) }
        let png = makePNG(width: 300, height: 200)
        let img = try #require(ClipBuilder.make(representations: [Representation(uti: PasteboardTypes.png, data: png)],
                                                sourceAppBundleID: nil, sourceAppName: nil, policy: CapturePolicy()))
        let imgIDopt = try store.mcpInsert(img)
        let imgID = try #require(imgIDopt)
        let reg = makeRegistry(store)
        guard case .image(let b64, _)? = reg.call(name: "get_item", arguments: ["id": n(imgID)]).content.first else {
            Issue.record("이미지 콘텐츠 아님"); return
        }
        let raw = try #require(Data(base64Encoded: b64))
        let size = try #require(pngSize(raw))
        #expect(size.0 == 300 && size.1 == 200)

        let file = try #require(ClipBuilder.make(
            representations: [Representation(uti: PasteboardTypes.fileURL, data: Data("file:///tmp/a%20b.txt".utf8))],
            sourceAppBundleID: nil, sourceAppName: nil, policy: CapturePolicy()))
        let fileIDopt = try store.mcpInsert(file)
        let fileID = try #require(fileIDopt)
        #expect(text(reg.call(name: "get_item", arguments: ["id": n(fileID)])) == "/tmp/a b.txt")
    }

    @Test func createTextItemRunsSecretCheck() throws {
        let (store, dir) = try makeTempStore()
        defer { try? FileManager.default.removeItem(at: dir) }
        let counter = ChangeCounter()
        let reg = makeRegistry(store, counter: counter)
        let r = reg.call(name: "create_text_item", arguments: ["text": .string(fakeAPIKey)])
        #expect(!r.isError)
        #expect(text(r).contains("비밀값으로 판정되어 MCP에서 숨김 처리됨"))
        #expect(ids(reg.call(name: "list_recent", arguments: [:])).isEmpty)
        #expect(!text(r).contains(fakeAPIKey))
        #expect(counter.count == 1)
        // 저장은 되어 있어야 한다(사용자 패널용)
        #expect(try store.search(SearchQuery()).count == 1)
    }

    @Test func createTextItemStoresVisibleAndPins() throws {
        let (store, dir) = try makeTempStore()
        defer { try? FileManager.default.removeItem(at: dir) }
        let board = try store.createPinboard(name: "notes", color: nil)
        let counter = ChangeCounter()
        let reg = makeRegistry(store, counter: counter)
        let r = reg.call(name: "create_text_item", arguments: ["text": .string("회의 메모입니다"), "pinboard": .string("notes")])
        #expect(!r.isError)
        let firstItem = try store.search(SearchQuery()).first
        let newID = try #require(firstItem?.id)
        #expect(text(r) == "{\"id\":\(newID)}")
        #expect(ids(reg.call(name: "list_pinboard_items", arguments: ["pinboard": n(board)])) == [newID])
        #expect(counter.count == 1)
        let stored = try store.item(id: newID)
        let item = try #require(stored)
        #expect(item.sourceAppBundleID == "local.hyoloui.clipdeck.mcp" && item.sourceAppName == "MCP")
    }

    @Test func createTextItemValidatesInput() throws {
        let (store, dir) = try makeTempStore()
        defer { try? FileManager.default.removeItem(at: dir) }
        let counter = ChangeCounter()
        let reg = makeRegistry(store, counter: counter)
        #expect(reg.call(name: "create_text_item", arguments: ["text": .string("")]).isError)
        #expect(reg.call(name: "create_text_item", arguments: ["text": .string("  \n ")]).isError)
        #expect(reg.call(name: "create_text_item", arguments: ["text": .string(String(repeating: "a", count: 100 * 1024 + 1))]).isError)
        #expect(reg.call(name: "create_text_item", arguments: ["text": .string("ok text"), "pinboard": .string("nope")]).isError)
        #expect(reg.call(name: "create_text_item", arguments: [:]).isError)
        #expect(counter.count == 0)
        #expect(try store.search(SearchQuery()).isEmpty)
        #expect(try store.pinboards().isEmpty) // 보드를 새로 만들지 않는다
    }

    @Test func copyToClipboardWritesReps() throws {
        let (store, dir) = try makeTempStore()
        defer { try? FileManager.default.removeItem(at: dir) }
        let id = try insertText(store, "copy me please")
        let clip = FakeClipboard()
        let counter = ChangeCounter()
        let reg = makeRegistry(store, clipboard: clip, counter: counter)
        #expect(!reg.call(name: "copy_to_clipboard", arguments: ["id": n(id)]).isError)
        #expect(clip.writes == [[Representation(uti: "public.utf8-plain-text", data: Data("copy me please".utf8))]])
        #expect(!reg.call(name: "copy_to_clipboard", arguments: ["text": .string("direct")]).isError)
        #expect(clip.writes.last == [Representation(uti: PasteboardTypes.plainText, data: Data("direct".utf8))])
        #expect(counter.count == 2)
        #expect(reg.call(name: "copy_to_clipboard", arguments: [:]).isError)
        #expect(reg.call(name: "copy_to_clipboard", arguments: ["id": n(id), "text": .string("x")]).isError)
        #expect(reg.call(name: "copy_to_clipboard", arguments: ["text": .string("")]).isError)
        #expect(clip.writes.count == 2)
    }

    @Test func addToPinboardWorksAndNeverCreatesBoard() throws {
        let (store, dir) = try makeTempStore()
        defer { try? FileManager.default.removeItem(at: dir) }
        let id = try insertText(store, "pin this")
        let board = try store.createPinboard(name: "keep", color: nil)
        let reg = makeRegistry(store)
        #expect(reg.call(name: "add_to_pinboard", arguments: ["id": n(id), "pinboard": .string("nope")]).isError)
        #expect(reg.call(name: "add_to_pinboard", arguments: ["id": n(id), "pinboard": n(9999)]).isError)
        #expect(try store.pinboards().count == 1)
        #expect(!reg.call(name: "add_to_pinboard", arguments: ["id": n(id), "pinboard": .string("keep")]).isError)
        #expect(ids(reg.call(name: "list_pinboard_items", arguments: ["pinboard": n(board)])) == [id])
        let missingBoard = reg.call(name: "list_pinboard_items", arguments: ["pinboard": .string("nope")])
        #expect(missingBoard.isError && text(missingBoard).contains("보드 없음"))
    }

    @Test func searchFilters() throws {
        let (store, dir) = try makeTempStore()
        defer { try? FileManager.default.removeItem(at: dir) }
        let old = try insertText(store, "alpha old entry", now: Date(timeIntervalSince1970: 1_700_000_000))
        let new = try insertText(store, "alpha new entry", now: Date(timeIntervalSince1970: 1_800_000_000))
        let reg = makeRegistry(store)
        #expect(Set(ids(reg.call(name: "search_items", arguments: ["query": .string("alpha")]))) == [old, new])
        #expect(ids(reg.call(name: "search_items", arguments: ["query": .string("alpha"), "since": .string("2026-01-01T00:00:00Z")])) == [new])
        #expect(ids(reg.call(name: "search_items", arguments: ["query": .string("alpha"), "kind": .string("image")])).isEmpty)
        #expect(ids(reg.call(name: "search_items", arguments: ["query": .string("alpha"), "app": .string("com.example.app")])).count == 2)
        let line = text(reg.call(name: "list_recent", arguments: ["limit": .number(1)]))
        #expect(line.contains("\"app\":\"com.example.app\"") && line.contains("\"last_used_at\":\"") && line.contains("\"kind\":\"text\""))
    }

    @Test func badArgumentsIsError() throws {
        let (store, dir) = try makeTempStore()
        defer { try? FileManager.default.removeItem(at: dir) }
        let reg = makeRegistry(store)
        let bad: [(String, [String: JSONValue])] = [
            ("get_item", ["id": .string("abc")]),
            ("get_item", ["id": .number(1.5)]),
            ("get_item", [:]),
            ("get_item", ["id": .bool(true)]),
            ("list_recent", ["limit": .string("5")]),
            ("list_recent", ["limit": .number(2.5)]),
            ("list_recent", ["kind": .string("video")]),
            ("search_items", ["query": .string("a"), "since": .string("yesterday")]),
            ("search_items", ["query": .number(5)]),
            ("list_pinboard_items", [:]),
            ("list_pinboard_items", ["pinboard": .bool(true)]),
            ("no_such_tool", [:]),
        ]
        for (name, args) in bad {
            let r = reg.call(name: name, arguments: args)
            #expect(r.isError, "\(name) \(args)")
        }
    }

    @Test func noDeleteTool() {
        let reg = ToolRegistry(store: try! ClipStore(directory: FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)),
                               clipboard: FakeClipboard(), notifyChange: {})
        let names = reg.definitions.map(\.name)
        #expect(names.count == 8)
        for name in names {
            for word in ["delete", "remove", "erase"] { #expect(!name.contains(word)) }
        }
        for d in reg.definitions {
            #expect(d.description.contains("/"))
            #expect(d.description.unicodeScalars.contains { $0.value >= 0xAC00 && $0.value <= 0xD7A3 })
        }
    }

    @Test func mcpStoreQueriesHideSecrets() throws {
        let (store, dir) = try makeTempStore()
        defer { try? FileManager.default.removeItem(at: dir) }
        let hidden = try insertText(store, "top secret thing", hidden: true)
        #expect(try store.mcpItem(id: hidden) == nil)
        #expect(try store.mcpRepresentations(itemID: hidden) == nil)
        #expect(try store.mcpPlainText(itemID: hidden) == nil)
        #expect(try store.mcpSearch(SearchQuery(text: "secret")).isEmpty)
        let clip = textClip("another secret thing", hidden: true)
        #expect(try store.mcpInsert(clip) == nil)
    }
}
