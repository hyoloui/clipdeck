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
        let id = try insertClip(store, clip)
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
        let imgID = try insertClip(store, img)
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
        let fileID = try insertClip(store, file)
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
        #expect(clip.writes.first?.first == Representation(uti: "public.utf8-plain-text", data: Data("copy me please".utf8)))
        #expect(clip.writes.first?.filter { $0.uti == PasteboardTypes.selfMarker }.count == 1)
        #expect(!reg.call(name: "copy_to_clipboard", arguments: ["text": .string("direct")]).isError)
        #expect(clip.writes.last?.first == Representation(uti: PasteboardTypes.plainText, data: Data("direct".utf8)))
        #expect(clip.writes.last?.filter { $0.uti == PasteboardTypes.selfMarker }.count == 1)
        #expect(counter.count == 1) // id 복사만 알린다
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

    @Test func noDeleteTool() throws {
        let (store, dir) = try makeTempStore()
        defer { try? FileManager.default.removeItem(at: dir) }
        let reg = makeRegistry(store)
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
    }

    @Test func createTextDoesNotProbeHidden() throws {
        let note = "meeting notes for tuesday"
        var shapes: [String] = []
        for withHidden in [false, true] {
            let (store, dir) = try makeTempStore()
            defer { try? FileManager.default.removeItem(at: dir) }
            var hiddenID: Int64?
            var before: ClipItem?
            if withHidden {
                // 숨김 앱에서 실제 캡처 경로(ClipBuilder)로 만든 행: content_hash가 텍스트의 SHA256이다
                let captured = try #require(ClipBuilder.make(
                    representations: [Representation(uti: PasteboardTypes.plainText, data: Data(note.utf8))],
                    sourceAppBundleID: "com.example.pm", sourceAppName: "PM",
                    policy: CapturePolicy(mcpHiddenBundleIDs: ["com.example.pm"])))
                #expect(captured.mcpHidden)
                let id = try insertClip(store, captured)
                hiddenID = id
                before = try store.item(id: id)
            }
            let reg = makeRegistry(store)
            let r = reg.call(name: "create_text_item", arguments: ["text": .string(note)])
            let body = text(r)
            shapes.append("\(r.isError)|\(r.content.count)|\(body.hasPrefix("{\"id\":"))")
            if let hiddenID {
                let after = try store.item(id: hiddenID)
                #expect(after?.lastUsedAt == before?.lastUsedAt)
                #expect(after?.useCount == before?.useCount)
                let listed = ids(reg.call(name: "list_recent", arguments: [:]))
                #expect(listed.count == 1 && !listed.contains(hiddenID))
            }
        }
        #expect(shapes[0] == shapes[1])
        #expect(shapes[0] == "false|1|true")
    }

    @Test func createTextTwiceMakesTwoRows() throws {
        let (store, dir) = try makeTempStore()
        defer { try? FileManager.default.removeItem(at: dir) }
        let reg = makeRegistry(store)
        let a = reg.call(name: "create_text_item", arguments: ["text": .string("same text here")])
        let b = reg.call(name: "create_text_item", arguments: ["text": .string("same text here")])
        #expect(!a.isError && !b.isError && text(a) != text(b))
        #expect(try store.search(SearchQuery()).count == 2)
    }

    @Test func secretWithPinboardSaysNotAdded() throws {
        let (store, dir) = try makeTempStore()
        defer { try? FileManager.default.removeItem(at: dir) }
        let board = try store.createPinboard(name: "x", color: nil)
        let reg = makeRegistry(store)
        let r = reg.call(name: "create_text_item", arguments: ["text": .string(fakeAPIKey), "pinboard": .string("x")])
        #expect(text(r).contains("보드에는 추가하지 않음"))
        let boards = try store.pinboards()
        #expect(boards.first { $0.id == board }?.itemCount == 0)
    }

    @Test func searchQueryOptionalAndBundleIDListed() throws {
        let (store, dir) = try makeTempStore()
        defer { try? FileManager.default.removeItem(at: dir) }
        try insertText(store, "some visible entry")
        let reg = makeRegistry(store)
        let search = try #require(reg.definitions.first { $0.name == "search_items" })
        guard case .object(let o) = search.inputSchema, case .array(let req)? = o["required"] else { Issue.record("schema"); return }
        #expect(!req.contains(.string("query")))
        #expect(search.description.contains("생략"))
        #expect(!reg.call(name: "search_items", arguments: [:]).isError)
        #expect(text(reg.call(name: "list_recent", arguments: [:])).contains("\"app_bundle_id\":\"com.example.app\""))
    }

    @Test func createTextNeverTouchesExistingRows() throws {
        let (store, dir) = try makeTempStore()
        defer { try? FileManager.default.removeItem(at: dir) }
        let board = try store.createPinboard(name: "b", color: nil)
        let reg = makeRegistry(store)
        let note = "meeting notes for tuesday"
        let first = reg.call(name: "create_text_item", arguments: ["text": .string(note)])
        let a = try #require(ids(ToolResult(content: [.text("[" + text(first) + "]")])).first)
        try store.setMCPHidden(id: a, true)
        let before = try store.item(id: a)
        let second = reg.call(name: "create_text_item", arguments: ["text": .string(note), "pinboard": .string("b")])
        let newID = try #require(ids(ToolResult(content: [.text("[" + text(second) + "]")])).first)
        #expect(newID != a)
        #expect(!reg.call(name: "get_item", arguments: ["id": n(newID)]).isError)
        let after = try store.item(id: a)
        #expect(after?.lastUsedAt == before?.lastUsedAt && after?.useCount == before?.useCount)
        #expect(ids(reg.call(name: "list_pinboard_items", arguments: ["pinboard": n(board)])) == [newID])
        let raw = try store.search(SearchQuery(pinboardID: board))
        #expect(raw.map(\.id) == [newID])
        let desc = try #require(reg.definitions.first { $0.name == "create_text_item" }).description
        #expect(desc.contains("하나 더"))
    }

    @Test func copyByIdMarksUsed() throws {
        let (store, dir) = try makeTempStore()
        defer { try? FileManager.default.removeItem(at: dir) }
        let id = try insertText(store, "used by copy")
        let before = try #require(try store.item(id: id)).useCount
        let reg = makeRegistry(store)
        #expect(!reg.call(name: "copy_to_clipboard", arguments: ["id": n(id)]).isError)
        #expect(try store.item(id: id)?.useCount == before + 1)
    }

    @Test func copyByTextLeavesNoRow() throws {
        let (store, dir) = try makeTempStore()
        defer { try? FileManager.default.removeItem(at: dir) }
        try insertText(store, "existing")
        let counter = ChangeCounter()
        let reg = makeRegistry(store, counter: counter)
        #expect(!reg.call(name: "copy_to_clipboard", arguments: ["text": .string("brand new text")]).isError)
        #expect(try store.search(SearchQuery()).count == 1)
        #expect(counter.count == 0)
        let desc = try #require(reg.definitions.first { $0.name == "copy_to_clipboard" }).description
        #expect(desc.contains("create_text_item"))
    }

    @Test func deletedAndHiddenLookTheSame() throws {
        let (a, dirA) = try makeTempStore()
        let (b, dirB) = try makeTempStore()
        defer { try? FileManager.default.removeItem(at: dirA); try? FileManager.default.removeItem(at: dirB) }
        // A: 보이는 행(1) + 숨김 행(2)
        try insertText(a, "보이는 항목")
        try insertText(a, "숨김 항목", hidden: true)
        // B: 보이는 행(1) + 넣었다 지운 행(2)
        try insertText(b, "보이는 항목")
        let gone = try insertText(b, "지울 항목")
        try b.delete(id: gone)
        let ra = makeRegistry(a).call(name: "create_text_item", arguments: ["text": .string("새 메모입니다")])
        let rb = makeRegistry(b).call(name: "create_text_item", arguments: ["text": .string("새 메모입니다")])
        #expect(text(ra) == text(rb))
        #expect(text(ra).contains("3"))
        let ga = makeRegistry(a).call(name: "get_item", arguments: ["id": .number(2)])
        let gb = makeRegistry(b).call(name: "get_item", arguments: ["id": .number(2)])
        #expect(ga == gb)
        #expect(ga.isError)
    }

    @Test func createTextRateLimitMessage() throws {
        let (store, dir) = try makeTempStore()
        defer { try? FileManager.default.removeItem(at: dir) }
        let reg = makeRegistry(store)
        for i in 0..<200 { #expect(!reg.call(name: "create_text_item", arguments: ["text": .string("메모 \(i)")]).isError) }
        let r = reg.call(name: "create_text_item", arguments: ["text": .string("초과 메모")])
        #expect(r.isError)
        #expect(text(r).contains("상한 200개"))
    }
}
