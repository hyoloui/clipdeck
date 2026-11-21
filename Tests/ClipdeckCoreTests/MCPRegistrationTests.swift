import Foundation
import Testing
@testable import ClipdeckCore

@Suite struct MCPRegistrationTests {
    @Test func 등록_명령_형태() {
        let cmd = MCPRegistration.command(executablePath: "/Applications/Clipdeck.app/Contents/MacOS/clipdeck-mcp")
        #expect(cmd == #"skillshare mcp add clipdeck --target claude --target codex --target antigravity -- "/Applications/Clipdeck.app/Contents/MacOS/clipdeck-mcp""#)
    }

    @Test func 공백이_든_경로도_따옴표로_감싼다() {
        let cmd = MCPRegistration.command(executablePath: "/Users/a b/Clipdeck.app/Contents/MacOS/clipdeck-mcp")
        #expect(cmd.hasSuffix(#"-- "/Users/a b/Clipdeck.app/Contents/MacOS/clipdeck-mcp""#))
    }

    @Test func 실행_파일_경로는_번들_기준이다() {
        let bundle = URL(fileURLWithPath: "/Applications/Clipdeck.app", isDirectory: true)
        #expect(MCPRegistration.executablePath(bundleURL: bundle) == "/Applications/Clipdeck.app/Contents/MacOS/clipdeck-mcp")
    }

    @Test func 항목_수는_전체와_MCP에_보이는_수를_센다() throws {
        let (store, dir) = try makeTempStore()
        defer { try? FileManager.default.removeItem(at: dir) }
        #expect(try store.itemCountSummary() == ItemCountSummary(total: 0, mcpVisible: 0))
        _ = try store.insert(textClip("a"))
        _ = try store.insert(textClip("b"))
        _ = try store.insert(textClip("secret", hidden: true))
        #expect(try store.itemCountSummary() == ItemCountSummary(total: 3, mcpVisible: 2))
    }
}
