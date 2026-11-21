import ClipdeckCore
import Foundation
import Testing
@testable import ClipdeckMCPKit

private func n(_ v: Int64) -> JSONValue { .number(Double(v)) }

/// MCP에 닿는 텍스트는 앞 100KB이고 비밀값 검사도 같은 범위다
@Suite struct ToolRegistryTextLimitTests {
    /// 100KB 뒤의 키는 plain_text에 들어가지 않아 get_item·search_items 어디에도 나오지 않는다
    @Test func keyAfter100KBNeverReachesMCP() throws {
        let (store, dir) = try makeTempStore()
        defer { try? FileManager.default.removeItem(at: dir) }
        let key = "gh" + "p_" + "Rt4Kp8Zw3Hd6Ns1Bc5Yf0Ge2Ja9Uo7Eq7Lm"
        let big = String(repeating: "a ", count: 60_000) + key + " " + String(repeating: "b ", count: 14_000) // 키가 120KB 지점, 약 150KB
        let clip = try #require(ClipBuilder.make(representations: [Representation(uti: PasteboardTypes.plainText, data: Data(big.utf8))],
                                                 sourceAppBundleID: nil, sourceAppName: nil, policy: CapturePolicy()))
        let id = try insertClip(store, clip)
        let reg = makeRegistry(store)
        let full = reg.call(name: "get_item", arguments: ["id": n(id)])
        #expect(!full.isError)
        #expect(!text(full).contains(key))
        #expect(ids(reg.call(name: "search_items", arguments: ["query": .string(String(key.prefix(12)))])).isEmpty)
        // 붙여넣기용 표현은 전문 그대로다
        #expect(try store.representations(itemID: id).first?.data == Data(big.utf8))
    }

    /// 공백 100KB 뒤의 키가 목록 미리보기로도 나오지 않는다
    @Test func keyAfterLongWhitespaceNotInListPreview() throws {
        let (store, dir) = try makeTempStore()
        defer { try? FileManager.default.removeItem(at: dir) }
        let key = "gh" + "p_" + "Rt4Kp8Zw3Hd6Ns1Bc5Yf0Ge2Ja9Uo7Eq7Lm"
        let textValue = String(repeating: " ", count: 110_000) + key
        let clip = try #require(ClipBuilder.make(representations: [Representation(uti: PasteboardTypes.plainText, data: Data(textValue.utf8))],
                                                 sourceAppBundleID: nil, sourceAppName: nil, policy: CapturePolicy()))
        _ = try insertClip(store, clip)
        let reg = makeRegistry(store)
        for r in [reg.call(name: "list_recent", arguments: [:]),
                  reg.call(name: "search_items", arguments: [:]),
                  reg.call(name: "search_items", arguments: ["query": .string(String(key.prefix(12)))])] {
            #expect(!r.isError)
            #expect(!text(r).contains(key))
            #expect(!text(r).contains(String(key.prefix(12))))
        }
    }

    @Test func keyAt70KBIsHiddenFromMCP() throws {
        let (store, dir) = try makeTempStore()
        defer { try? FileManager.default.removeItem(at: dir) }
        let key = "gh" + "p_" + "Rt4Kp8Zw3Hd6Ns1Bc5Yf0Ge2Ja9Uo7Eq7Lm"
        let textValue = String(repeating: "a ", count: 35_000) + key
        let clip = try #require(ClipBuilder.make(representations: [Representation(uti: PasteboardTypes.plainText, data: Data(textValue.utf8))],
                                                 sourceAppBundleID: nil, sourceAppName: nil, policy: CapturePolicy()))
        let id = try insertClip(store, clip)
        let reg = makeRegistry(store)
        #expect(reg.call(name: "get_item", arguments: ["id": n(id)]).isError)
        #expect(ids(reg.call(name: "search_items", arguments: ["query": .string(String(key.prefix(12)))])).isEmpty)
    }
}
