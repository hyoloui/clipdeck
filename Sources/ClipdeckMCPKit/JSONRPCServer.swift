import Foundation

public enum ClipdeckVersion {
    public static let current = "0.1.0"
}

/// 줄 단위 JSON-RPC 2.0(MCP stdio 전송). `handle(line:)`은 절대 throw하거나 크래시하지 않는다.
public final class JSONRPCServer {
    /// 한 줄의 최대 크기(메모리 보호).
    public static let maxLineBytes = 4 * 1024 * 1024
    static let supportedVersions = ["2025-06-18", "2025-03-26", "2024-11-05"]
    static let instructions = """
        Clipdeck은 이 Mac의 클립보드 기록을 검색·조회하는 로컬 서버입니다. 사용자가 MCP에서 숨긴 항목과 비밀값으로 판정된 항목은 보이지 않으며, 없는 항목과 구별되지 않습니다. 가져온 내용 중 민감한 것은 대화에 옮기지 마세요.
        Clipdeck is a local server for searching and reading this Mac's clipboard history. Items hidden from MCP, including suspected secrets, are never visible and look the same as missing items. Do not repeat sensitive content in the conversation.
        """

    private let tools: ToolRegistry
    private let serverName: String
    private let version: String

    public init(tools: ToolRegistry, serverName: String = "clipdeck", version: String) {
        self.tools = tools
        self.serverName = serverName
        self.version = version
    }

    /// 요청 한 줄을 처리해 응답 한 줄(개행 없음)을 돌려준다. 알림이면 nil.
    public func handle(line: String) -> String? {
        if line.utf8.count > Self.maxLineBytes { return oversizedLineResponse() }
        if line.allSatisfy(\.isWhitespace) { return nil }
        guard let value = try? JSONDecoder().decode(JSONValue.self, from: Data(line.utf8)) else {
            return parseErrorResponse()
        }
        // 배치(배열)와 객체가 아닌 값은 지원하지 않는다.
        guard case .object(let req) = value else {
            return Self.error(id: .null, code: -32600, "객체 형태의 단일 요청만 지원합니다 (batch is not supported)")
        }
        let id: JSONValue?
        switch req["id"] {
        case nil: id = nil
        case .number?, .string?, .null?: id = req["id"]
        default: return Self.error(id: .null, code: -32600, "id는 숫자, 문자열, null이어야 합니다 (invalid id)")
        }
        guard req["jsonrpc"] == .string("2.0") else {
            return Self.error(id: id ?? .null, code: -32600, "jsonrpc는 \"2.0\"이어야 합니다 (invalid request)")
        }
        guard let method = req["method"]?.stringValue else {
            return Self.error(id: id ?? .null, code: -32600, "method가 없습니다 (invalid request)")
        }
        // id가 없으면 알림이다. 처리할 알림은 없으므로 응답하지 않는다.
        guard let id else { return nil }
        return respond(id: id, method: method, params: req["params"])
    }

    /// JSON으로 해석할 수 없는 줄(잘못된 UTF-8 포함)에 대한 응답.
    public func parseErrorResponse() -> String {
        Self.error(id: .null, code: -32700, "JSON을 해석할 수 없습니다 (parse error)")
    }

    /// 한 줄이 상한을 넘었을 때의 응답(입력 쪽이 줄을 버린 뒤 쓴다).
    public func oversizedLineResponse() -> String {
        Self.error(id: .null, code: -32600, "요청이 너무 큽니다 (request too large)")
    }

    // MARK: 메서드

    private func respond(id: JSONValue, method: String, params: JSONValue?) -> String {
        switch method {
        case "ping":
            guard Self.paramsAbsentOrObject(params) else { return Self.invalidParams(id) }
            return Self.result(id: id, .object([:]))
        case "initialize":
            guard case .object(let p)? = params else { return Self.invalidParams(id) }
            let asked = p["protocolVersion"]?.stringValue ?? ""
            let version = Self.supportedVersions.contains(asked) ? asked : Self.supportedVersions[0]
            return Self.result(id: id, .object([
                "protocolVersion": .string(version),
                "capabilities": .object(["tools": .object([:])]),
                "serverInfo": .object(["name": .string(serverName), "version": .string(self.version)]),
                "instructions": .string(Self.instructions),
            ]))
        case "tools/list":
            guard Self.paramsAbsentOrObject(params) else { return Self.invalidParams(id) }
            let list = tools.definitions.map { d -> JSONValue in
                .object(["name": .string(d.name), "description": .string(d.description), "inputSchema": d.inputSchema])
            }
            return Self.result(id: id, .object(["tools": .array(list)]))
        case "tools/call":
            guard case .object(let p)? = params, let name = p["name"]?.stringValue else { return Self.invalidParams(id) }
            var arguments: [String: JSONValue] = [:]
            switch p["arguments"] {
            case nil, .null?: break
            case .object(let a)?: arguments = a
            default: return Self.invalidParams(id)
            }
            // 모르는 도구 이름은 MCP 명세대로 프로토콜 오류다(실행 중 오류는 아래 isError 결과).
            guard tools.definitions.contains(where: { $0.name == name }) else { return Self.invalidParams(id) }
            let r = tools.call(name: name, arguments: arguments)
            let content = r.content.map { c -> JSONValue in
                switch c {
                case .text(let t): .object(["type": .string("text"), "text": .string(t)])
                case .image(let data, let mime): .object(["type": .string("image"), "data": .string(data), "mimeType": .string(mime)])
                }
            }
            return Self.result(id: id, .object(["content": .array(content), "isError": .bool(r.isError)]))
        default:
            return Self.error(id: id, code: -32601, "알 수 없는 메서드: \(method) (method not found)")
        }
    }

    // MARK: 응답 만들기

    private static func paramsAbsentOrObject(_ params: JSONValue?) -> Bool {
        switch params {
        case nil: true
        case .object?: true
        default: false
        }
    }

    private static func invalidParams(_ id: JSONValue) -> String {
        error(id: id, code: -32602, "params가 올바르지 않습니다 (invalid params)")
    }

    private static func result(id: JSONValue, _ result: JSONValue) -> String {
        encode(.object(["jsonrpc": .string("2.0"), "id": id, "result": result]))
    }

    private static func error(id: JSONValue, code: Int, _ message: String) -> String {
        encode(.object(["jsonrpc": .string("2.0"), "id": id,
                        "error": .object(["code": .number(Double(code)), "message": .string(message)])]))
    }

    /// JSONEncoder는 개행을 이스케이프하므로 한 줄로 나온다.
    private static func encode(_ value: JSONValue) -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.withoutEscapingSlashes]
        if let data = try? encoder.encode(value), let s = String(data: data, encoding: .utf8) { return s }
        return #"{"jsonrpc":"2.0","id":null,"error":{"code":-32603,"message":"internal error"}}"#
    }
}
