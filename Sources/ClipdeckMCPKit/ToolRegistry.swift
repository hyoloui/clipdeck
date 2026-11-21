import ClipdeckCore
import Foundation
import ImageIO

public struct ToolDefinition: Sendable {
    public var name: String
    public var description: String
    public var inputSchema: JSONValue
    public init(name: String, description: String, inputSchema: JSONValue) {
        self.name = name
        self.description = description
        self.inputSchema = inputSchema
    }
}

public enum ToolContent: Equatable, Sendable {
    case text(String)
    case image(base64: String, mimeType: String)
}

public struct ToolResult: Equatable, Sendable {
    public var content: [ToolContent]
    public var isError: Bool
    public init(content: [ToolContent], isError: Bool = false) {
        self.content = content
        self.isError = isError
    }
}

/// 사용자에게 그대로 보여줘도 되는 오류 문구만 담는다(경로·SQL 금지).
struct ToolError: Error {
    let message: String
    init(_ message: String) { self.message = message }
}

/// MCP 도구 8개. 저장소 조회는 `store.mcp…` 함수만 쓴다(숨김 항목 차단은 ClipStore+MCP.swift 한 곳에서만 한다).
public final class ToolRegistry {
    static let maxLimit = 100
    static let defaultLimit = 20
    /// 텍스트 상한(100KB). 저장되는 `plain_text`·비밀값 검사 범위와 같은 값이다.
    static let maxTextBytes = ClipLimits.plainTextBytes
    static let maxImagePixels = 1024
    static let previewChars = 200
    /// 항목이 없을 때의 문구. 숨김 항목도 같은 경로로 이 문구가 나온다.
    static let itemNotFound = "항목 없음: 해당 id의 항목을 찾을 수 없습니다 (item not found)"
    static let boardNotFound = "보드 없음: 해당 Pinboard를 찾을 수 없습니다 (pinboard not found)"

    private let store: ClipStore
    private let clipboard: ClipboardWriting
    private let notifyChange: () -> Void

    public init(store: ClipStore, clipboard: ClipboardWriting, notifyChange: @escaping () -> Void) {
        self.store = store
        self.clipboard = clipboard
        self.notifyChange = notifyChange
    }

    // MARK: 정의

    public var definitions: [ToolDefinition] {
        let listProps: [Prop] = [
            ("limit", "integer", "최대 개수(기본 20, 최대 100) / max results (default 20, max 100)"),
        ]
        return [
            ToolDefinition(name: "search_items",
                description: "클립보드 기록을 검색한다(query를 생략하면 최근 항목). 사용자가 \"아까 복사한 거\", \"클립보드에서 찾아줘\"라고 할 때 쓴다. / Search clipboard history by text (omit query for recent items). Use when the user refers to something they copied earlier.",
                inputSchema: Self.schema([
                    ("query", "string", "검색어, 생략하면 최근 항목 / search text, omit for recent items"),
                    ("kind", "string", "text, link, image, file, color 중 하나 / one of text, link, image, file, color"),
                    ("app", "string", "출처 앱 번들 ID(결과의 app_bundle_id 값) / source app bundle ID (the result field app_bundle_id)"),
                    ("pinboard", "integer|string", "Pinboard id 또는 이름 / pinboard id or name"),
                    ("since", "string", "이 시각 이후(ISO8601, 예 2026-11-21T00:00:00Z) / only items used since (ISO8601)"),
                ] + listProps, required: [])),
            ToolDefinition(name: "list_recent",
                description: "최근에 쓴 클립보드 항목을 최신순으로 나열한다. / List the most recently used clipboard items.",
                inputSchema: Self.schema([("kind", "string", "text, link, image, file, color 중 하나 / one of the kinds")] + listProps, required: [])),
            ToolDefinition(name: "get_item",
                description: "항목 하나의 내용을 가져온다. 텍스트는 전문(최대 100KB), 이미지는 긴 변 1024px로 축소, 파일은 경로 목록. / Get one item's content: full text (max 100KB), image scaled to 1024px, or file paths.",
                inputSchema: Self.schema([("id", "integer", "항목 id / item id")], required: ["id"])),
            ToolDefinition(name: "list_pinboards",
                description: "Pinboard(보드) 목록과 항목 수를 돌려준다. / List pinboards with their item counts.",
                inputSchema: Self.schema([], required: [])),
            ToolDefinition(name: "list_pinboard_items",
                description: "한 Pinboard에 들어 있는 항목을 나열한다. / List the items in one pinboard.",
                inputSchema: Self.schema([("pinboard", "integer|string", "Pinboard id 또는 이름 / pinboard id or name")] + listProps, required: ["pinboard"])),
            ToolDefinition(name: "copy_to_clipboard",
                description: "기존 항목(id) 또는 텍스트를 시스템 클립보드에 복사한다. 사용자가 ⌘V로 붙여넣는다. id와 text 중 하나만 준다. text로 복사한 내용은 기록에 남지 않는다(남기려면 create_text_item). / Copy an existing item (id) or a text to the system clipboard; the user then pastes with Cmd+V. Give exactly one of id or text. A copied text is not saved to history (use create_text_item to keep it).",
                inputSchema: Self.schema([
                    ("id", "integer", "복사할 항목 id / item id to copy"),
                    ("text", "string", "직접 복사할 텍스트(최대 100KB) / text to copy (max 100KB)"),
                ], required: [])),
            ToolDefinition(name: "create_text_item",
                description: "텍스트를 새 클립보드 항목으로 저장한다. 비밀값으로 보이면 MCP에서 숨겨진다. 같은 텍스트로 다시 호출하면 항목이 하나 더 생긴다. / Save a text as a new clipboard item. Text that looks like a secret is hidden from MCP. Calling again with the same text creates one more item.",
                inputSchema: Self.schema([
                    ("text", "string", "저장할 텍스트(최대 100KB) / text to save (max 100KB)"),
                    ("pinboard", "integer|string", "넣을 Pinboard id 또는 이름(없는 보드는 만들지 않음) / pinboard to add to (never created)"),
                ], required: ["text"])),
            ToolDefinition(name: "add_to_pinboard",
                description: "기존 항목을 Pinboard에 넣는다. / Add an existing item to a pinboard.",
                inputSchema: Self.schema([
                    ("id", "integer", "항목 id / item id"),
                    ("pinboard", "integer|string", "Pinboard id 또는 이름 / pinboard id or name"),
                ], required: ["id", "pinboard"])),
        ]
    }

    typealias Prop = (name: String, type: String, description: String)

    private static func schema(_ props: [Prop], required: [String]) -> JSONValue {
        var properties: [String: JSONValue] = [:]
        for p in props {
            let type: JSONValue = p.type.contains("|")
                ? .array(p.type.split(separator: "|").map { .string(String($0)) }) : .string(p.type)
            properties[p.name] = .object(["type": type, "description": .string(p.description)])
        }
        return .object(["type": .string("object"), "properties": .object(properties),
                        "required": .array(required.map { .string($0) })])
    }

    // MARK: 호출

    /// 절대 throw하지 않는다. 내부 오류는 경로·SQL 없는 일반 문구로 바꾼다.
    public func call(name: String, arguments: [String: JSONValue]) -> ToolResult {
        do {
            let args = Args(arguments)
            switch name {
            case "search_items": return try searchItems(args)
            case "list_recent": return try listRecent(args)
            case "get_item": return try getItem(args)
            case "list_pinboards": return try listPinboards()
            case "list_pinboard_items": return try listPinboardItems(args)
            case "copy_to_clipboard": return try copyToClipboard(args)
            case "create_text_item": return try createTextItem(args)
            case "add_to_pinboard": return try addToPinboard(args)
            default: throw ToolError("알 수 없는 도구: \(name) (unknown tool)")
            }
        } catch let e as ToolError {
            return Self.failure(e.message)
        } catch {
            return Self.failure("내부 오류로 처리하지 못했습니다 (internal error)")
        }
    }

    private static func failure(_ message: String) -> ToolResult {
        ToolResult(content: [.text(message)], isError: true)
    }

    // MARK: 목록 도구

    private func searchItems(_ args: Args) throws -> ToolResult {
        var q = SearchQuery(text: try args.string("query") ?? "", limit: try args.limit())
        q.kind = try args.kind()
        q.appBundleID = try args.string("app")
        q.since = try args.since()
        if let board = args["pinboard"] { q.pinboardID = try resolveBoard(board).id }
        return try Self.itemList(store.mcpSearch(q))
    }

    private func listRecent(_ args: Args) throws -> ToolResult {
        try Self.itemList(store.mcpSearch(SearchQuery(kind: try args.kind(), limit: try args.limit())))
    }

    private func listPinboardItems(_ args: Args) throws -> ToolResult {
        guard let board = args["pinboard"] else { throw ToolError("pinboard 인자가 필요합니다 (pinboard is required)") }
        let id = try resolveBoard(board).id
        return try Self.itemList(store.mcpSearch(SearchQuery(pinboardID: id, limit: try args.limit())))
    }

    private func listPinboards() throws -> ToolResult {
        let boards = try store.mcpPinboards().map { b -> JSONValue in
            .object(["id": .number(Double(b.id)), "name": .string(b.name), "item_count": .number(Double(b.itemCount))])
        }
        return try Self.json(.array(boards))
    }

    private static func itemList(_ items: [ClipItem]) throws -> ToolResult {
        let formatter = ISO8601DateFormatter()
        return try json(.array(items.map { item in
            .object([
                "id": .number(Double(item.id)),
                "kind": .string(item.kind.rawValue),
                "preview": .string(String(item.preview.prefix(previewChars))),
                "app": (item.sourceAppName ?? item.sourceAppBundleID).map { .string($0) } ?? .null,
                "app_bundle_id": item.sourceAppBundleID.map { .string($0) } ?? .null,
                "last_used_at": .string(formatter.string(from: item.lastUsedAt)),
            ])
        }))
    }

    private static func json(_ value: JSONValue) throws -> ToolResult {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return ToolResult(content: [.text(String(decoding: try encoder.encode(value), as: UTF8.self))])
    }

    // MARK: 조회 도구

    private func getItem(_ args: Args) throws -> ToolResult {
        let id = try args.requiredInt("id")
        guard let item = try store.mcpItem(id: id) else { throw ToolError(Self.itemNotFound) }
        switch item.kind {
        case .text, .link:
            let text = try store.mcpPlainText(itemID: id) ?? item.preview
            let (body, cut) = Self.truncate(text)
            let note = cut ? "\n\n[잘림: 전체 \(text.utf8.count)바이트 중 앞 \(Self.maxTextBytes)바이트만 표시 / truncated to \(Self.maxTextBytes) bytes]" : ""
            return ToolResult(content: [.text(body + note)])
        case .image:
            let reps = try store.mcpRepresentations(itemID: id) ?? []
            guard let rep = reps.first(where: { $0.uti == PasteboardTypes.png }) ?? reps.first(where: { $0.uti == PasteboardTypes.tiff }),
                  let png = Self.scaledPNG(rep.data) else { throw ToolError("이미지를 읽을 수 없습니다 (cannot read image)") }
            return ToolResult(content: [.image(base64: png.base64EncodedString(), mimeType: "image/png")])
        case .file:
            let reps = try store.mcpRepresentations(itemID: id) ?? []
            let paths = reps.filter { $0.uti == PasteboardTypes.fileURL }
                .compactMap { String(data: $0.data, encoding: .utf8) }
                .map { URL(string: $0)?.path ?? $0 }
            return ToolResult(content: [.text(paths.joined(separator: "\n"))])
        case .color:
            return ToolResult(content: [.text(item.preview)])
        }
    }

    /// 100KB를 넘으면 문자 경계에서 자른다(예전에 전문이 저장된 행 대비).
    static func truncate(_ s: String) -> (String, Bool) {
        guard s.utf8.count > maxTextBytes else { return (s, false) }
        return (ClipLimits.prefix(s, maxBytes: maxTextBytes), true)
    }

    /// 긴 변이 1024px를 넘으면 줄이고, 아니면 그대로 PNG로 인코딩한다.
    static func scaledPNG(_ data: Data) -> Data? {
        guard let src = CGImageSourceCreateWithData(data as CFData, nil),
              let props = CGImageSourceCopyPropertiesAtIndex(src, 0, nil) as? [CFString: Any],
              let w = props[kCGImagePropertyPixelWidth] as? Int,
              let h = props[kCGImagePropertyPixelHeight] as? Int else { return nil }
        let image: CGImage?
        if max(w, h) > maxImagePixels {
            image = ImageThumbnail.make(data: data, maxPixel: maxImagePixels)
        } else {
            image = CGImageSourceCreateImageAtIndex(src, 0, nil)
        }
        guard let image else { return nil }
        let out = NSMutableData()
        guard let dest = CGImageDestinationCreateWithData(out, "public.png" as CFString, 1, nil) else { return nil }
        CGImageDestinationAddImage(dest, image, nil)
        guard CGImageDestinationFinalize(dest) else { return nil }
        return out as Data
    }

    // MARK: 쓰기 도구

    private func copyToClipboard(_ args: Args) throws -> ToolResult {
        let id = try args.int("id")
        let text = try args.string("text")
        let reps: [Representation]
        switch (id, text) {
        case (.some(let id), nil):
            guard let item = try store.mcpItem(id: id), let found = try store.mcpRepresentations(itemID: item.id), !found.isEmpty
            else { throw ToolError(Self.itemNotFound) }
            reps = found
        case (nil, .some(let text)):
            reps = [Representation(uti: PasteboardTypes.plainText, data: Data(try Self.validText(text).utf8))]
        default:
            throw ToolError("id와 text 중 하나만 지정해야 합니다 (give exactly one of id or text)")
        }
        clipboard.write(ClipboardPayload.withSelfMarker(reps))
        // id 복사만 사용 기록을 남기고 알린다. text 복사는 기록에 남지 않는다.
        if let id {
            try store.mcpMarkUsed(id: id)
            notifyChange()
        }
        return ToolResult(content: [.text("클립보드에 복사했습니다. 사용자가 ⌘V로 붙여넣을 수 있습니다. (copied to the clipboard)")])
    }

    private func createTextItem(_ args: Args) throws -> ToolResult {
        let text = try Self.validText(try args.requiredString("text"))
        let board = try args["pinboard"].map { try resolveBoard($0) }
        switch try store.mcpCreateText(text) {
        case .rejected:
            throw ToolError("저장할 수 있는 텍스트가 아닙니다 (text cannot be saved)")
        case .rateLimited:
            throw ToolError("최근 1시간 동안 만든 항목이 너무 많습니다(상한 200개). 잠시 뒤 다시 시도하세요. (too many items created in the last hour; limit 200)")
        case .hidden:
            notifyChange()
            let note = board == nil ? "" : " 보드에는 추가하지 않음 (not added to the pinboard)."
            return ToolResult(content: [.text("저장했지만 비밀값으로 판정되어 MCP에서 숨김 처리됨 (saved, but hidden from MCP as a suspected secret)." + note)])
        case .created(let id):
            if let board { try store.add(itemID: id, toPinboard: board.id) }
            notifyChange()
            return try Self.json(.object(["id": .number(Double(id))]))
        }
    }

    private func addToPinboard(_ args: Args) throws -> ToolResult {
        let id = try args.requiredInt("id")
        guard let board = args["pinboard"] else { throw ToolError("pinboard 인자가 필요합니다 (pinboard is required)") }
        let target = try resolveBoard(board)
        guard let item = try store.mcpItem(id: id) else { throw ToolError(Self.itemNotFound) }
        try store.add(itemID: item.id, toPinboard: target.id)
        notifyChange()
        return ToolResult(content: [.text("항목 \(item.id)을(를) '\(target.name)' 보드에 넣었습니다. (added to pinboard)")])
    }

    // MARK: 공통

    private static func validText(_ text: String) throws -> String {
        if text.allSatisfy(\.isWhitespace) { throw ToolError("텍스트가 비어 있습니다 (text is empty)") }
        if text.utf8.count > maxTextBytes { throw ToolError("텍스트가 100KB를 넘습니다 (text exceeds 100KB)") }
        return text
    }

    /// id(숫자) 또는 이름(문자열)으로 Pinboard를 찾는다. 없으면 오류이며 새로 만들지 않는다.
    private func resolveBoard(_ value: JSONValue) throws -> Pinboard {
        let boards = try store.mcpPinboards()
        let found: Pinboard?
        switch value {
        case .string(let name): found = boards.first { $0.name == name }
        case .number:
            guard let id = value.intValue else { throw ToolError("pinboard는 정수 id 또는 이름이어야 합니다 (pinboard must be an integer id or a name)") }
            found = boards.first { $0.id == id }
        default: throw ToolError("pinboard는 정수 id 또는 이름이어야 합니다 (pinboard must be an integer id or a name)")
        }
        guard let found else { throw ToolError(Self.boardNotFound) }
        return found
    }

    /// 인자 추출. 타입이 틀리면 ToolError를 던진다.
    struct Args {
        let values: [String: JSONValue]
        init(_ values: [String: JSONValue]) { self.values = values }

        subscript(_ key: String) -> JSONValue? {
            if case .null? = values[key] { return nil }
            return values[key]
        }

        func string(_ key: String) throws -> String? {
            guard let v = self[key] else { return nil }
            guard let s = v.stringValue else { throw ToolError("\(key)는 문자열이어야 합니다 (\(key) must be a string)") }
            return s
        }

        func requiredString(_ key: String) throws -> String {
            guard let s = try string(key) else { throw ToolError("\(key) 인자가 필요합니다 (\(key) is required)") }
            return s
        }

        func int(_ key: String) throws -> Int64? {
            guard let v = self[key] else { return nil }
            guard let i = v.intValue else { throw ToolError("\(key)는 정수여야 합니다 (\(key) must be an integer)") }
            return i
        }

        func requiredInt(_ key: String) throws -> Int64 {
            guard let i = try int(key) else { throw ToolError("\(key) 인자가 필요합니다 (\(key) is required)") }
            return i
        }

        func limit() throws -> Int {
            let n = try int("limit") ?? Int64(ToolRegistry.defaultLimit)
            return Int(min(max(n, 1), Int64(ToolRegistry.maxLimit)))
        }

        func kind() throws -> ItemKind? {
            guard let s = try string("kind") else { return nil }
            guard let k = ItemKind(rawValue: s) else {
                throw ToolError("kind는 \(ItemKind.allCases.map(\.rawValue).joined(separator: ", ")) 중 하나여야 합니다 (invalid kind)")
            }
            return k
        }

        func since() throws -> Date? {
            guard let s = try string("since") else { return nil }
            let plain = ISO8601DateFormatter()
            let fractional = ISO8601DateFormatter()
            fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            guard let d = plain.date(from: s) ?? fractional.date(from: s) else {
                throw ToolError("since는 ISO8601 형식이어야 합니다 (예 2026-11-21T00:00:00Z) (since must be ISO8601)")
            }
            return d
        }
    }
}
