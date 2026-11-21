import Foundation
import Testing
@testable import ClipdeckMCPKit

@Suite struct JSONRPCServerTests {
    private func makeServer() throws -> (JSONRPCServer, URL) {
        let (store, dir) = try makeTempStore()
        return (JSONRPCServer(tools: makeRegistry(store), version: "9.9.9"), dir)
    }

    private func parse(_ line: String?) throws -> [String: JSONValue] {
        let s = try #require(line)
        #expect(!s.contains("\n"))
        guard case .object(let o) = try JSONDecoder().decode(JSONValue.self, from: Data(s.utf8)) else {
            Issue.record("객체가 아님"); return [:]
        }
        return o
    }

    private func errorCode(_ o: [String: JSONValue]) -> Int64? {
        if case .object(let e)? = o["error"] { e["code"]?.intValue } else { nil }
    }

    @Test func initializeEchoesVersion() throws {
        let (server, dir) = try makeServer()
        defer { try? FileManager.default.removeItem(at: dir) }
        for (asked, expected) in [("2025-03-26", "2025-03-26"), ("2024-11-05", "2024-11-05"),
                                  ("2025-06-18", "2025-06-18"), ("1999-01-01", "2025-06-18")] {
            let r = try parse(server.handle(line: #"{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"\#(asked)","capabilities":{},"clientInfo":{"name":"t","version":"0"}}}"#))
            #expect(r["id"] == .number(1))
            guard case .object(let res)? = r["result"] else { Issue.record("result 없음"); return }
            #expect(res["protocolVersion"] == .string(expected))
            #expect(res["capabilities"] == .object(["tools": .object([:])]))
            #expect(res["serverInfo"] == .object(["name": .string("clipdeck"), "version": .string("9.9.9")]))
            #expect(res["instructions"]?.stringValue?.isEmpty == false)
        }
    }

    @Test func toolsListHasEight() throws {
        let (server, dir) = try makeServer()
        defer { try? FileManager.default.removeItem(at: dir) }
        let r = try parse(server.handle(line: #"{"jsonrpc":"2.0","id":2,"method":"tools/list"}"#))
        guard case .object(let res)? = r["result"], case .array(let tools)? = res["tools"] else { Issue.record("tools 없음"); return }
        #expect(tools.count == 8)
        for case .object(let t) in tools {
            #expect(t["name"]?.stringValue != nil)
            #expect(t["description"]?.stringValue != nil)
            #expect(t["inputSchema"] != nil)
        }
    }

    @Test func malformedLineReturnsParseError() throws {
        let (server, dir) = try makeServer()
        defer { try? FileManager.default.removeItem(at: dir) }
        let r = try parse(server.handle(line: "{oops"))
        #expect(r["id"] == .null)
        #expect(errorCode(r) == -32700)
        let p = try parse(server.handle(line: #"{"jsonrpc":"2.0","id":3,"method":"ping"}"#))
        #expect(p["result"] == .object([:]))
        #expect(p["id"] == .number(3))
    }

    @Test func unknownMethod() throws {
        let (server, dir) = try makeServer()
        defer { try? FileManager.default.removeItem(at: dir) }
        let r = try parse(server.handle(line: #"{"jsonrpc":"2.0","id":"abc","method":"nope/x"}"#))
        #expect(errorCode(r) == -32601)
        #expect(r["id"] == .string("abc"))
    }

    @Test func notificationReturnsNil() throws {
        let (server, dir) = try makeServer()
        defer { try? FileManager.default.removeItem(at: dir) }
        #expect(server.handle(line: #"{"jsonrpc":"2.0","method":"notifications/initialized"}"#) == nil)
        #expect(server.handle(line: #"{"jsonrpc":"2.0","method":"nope/x"}"#) == nil)
        #expect(server.handle(line: "   ") == nil)
    }

    @Test func toolsCallRoundTrip() throws {
        let (server, dir) = try makeServer()
        defer { try? FileManager.default.removeItem(at: dir) }
        let r = try parse(server.handle(line: #"{"jsonrpc":"2.0","id":4,"method":"tools/call","params":{"name":"list_recent","arguments":{}}}"#))
        guard case .object(let res)? = r["result"], case .array(let content)? = res["content"],
              case .object(let first)? = content.first else { Issue.record("content 없음"); return }
        #expect(first["type"] == .string("text"))
        #expect(res["isError"] == .bool(false))
        // arguments 없이도 같다
        let r2 = try parse(server.handle(line: #"{"jsonrpc":"2.0","id":5,"method":"tools/call","params":{"name":"list_recent"}}"#))
        #expect(r2["error"] == nil)
    }

    @Test func toolsCallErrorsAndImage() throws {
        let (server, dir) = try makeServer()
        defer { try? FileManager.default.removeItem(at: dir) }
        let unknown = try parse(server.handle(line: #"{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"zzz"}}"#))
        guard case .object(let res)? = unknown["result"] else { Issue.record("result 없음"); return }
        #expect(res["isError"] == .bool(true))
        #expect(errorCode(try parse(server.handle(line: #"{"jsonrpc":"2.0","id":1,"method":"tools/call"}"#))) == -32602)
        #expect(errorCode(try parse(server.handle(line: #"{"jsonrpc":"2.0","id":1,"method":"tools/call","params":[1]}"#))) == -32602)
        #expect(errorCode(try parse(server.handle(line: #"{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"arguments":{}}}"#))) == -32602)
        #expect(errorCode(try parse(server.handle(line: #"{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"list_recent","arguments":5}}"#))) == -32602)
        #expect(errorCode(try parse(server.handle(line: #"{"jsonrpc":"2.0","id":1,"method":"initialize"}"#))) == -32602)
    }

    @Test func idsAreEchoedAndBadShapesRejected() throws {
        let (server, dir) = try makeServer()
        defer { try? FileManager.default.removeItem(at: dir) }
        #expect(try parse(server.handle(line: #"{"jsonrpc":"2.0","id":null,"method":"ping"}"#))["id"] == .null)
        #expect(try parse(server.handle(line: #"{"jsonrpc":"2.0","id":"x-1","method":"ping"}"#))["id"] == .string("x-1"))
        // 배치, 비객체, method 누락
        for line in [#"[{"jsonrpc":"2.0","id":1,"method":"ping"}]"#, "42", #""s""#, "null"] {
            let r = try parse(server.handle(line: line))
            #expect(errorCode(r) == -32600)
            #expect(r["id"] == .null)
        }
        #expect(errorCode(try parse(server.handle(line: #"{"jsonrpc":"2.0","id":7}"#))) == -32600)
        #expect(errorCode(try parse(server.handle(line: #"{"jsonrpc":"2.0","id":{"a":1},"method":"ping"}"#))) == -32600)
    }

    @Test func oversizedLineIsRejected() throws {
        let (server, dir) = try makeServer()
        defer { try? FileManager.default.removeItem(at: dir) }
        let big = #"{"jsonrpc":"2.0","id":1,"method":"ping","x":""# + String(repeating: "a", count: JSONRPCServer.maxLineBytes) + #""}"#
        let r = try parse(server.handle(line: big))
        #expect(errorCode(r) == -32600)
        #expect(r["id"] == .null)
        #expect(try parse(server.oversizedLineResponse())["error"] != nil)
    }

    @Test func createThenListThroughRPC() throws {
        let (server, dir) = try makeServer()
        defer { try? FileManager.default.removeItem(at: dir) }
        _ = server.handle(line: #"{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"create_text_item","arguments":{"text":"hello from mcp"}}}"#)
        let r = try #require(server.handle(line: #"{"jsonrpc":"2.0","id":2,"method":"tools/call","params":{"name":"list_recent"}}"#))
        #expect(r.contains("hello from mcp"))
    }
}
