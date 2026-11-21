import Foundation

/// MCP 서버 등록에 쓰는 값. 설정 창의 MCP 탭이 보여 준다.
public enum MCPRegistration {
    /// 앱 번들 안의 MCP 서버 실행 파일 절대 경로
    public static func executablePath(bundleURL: URL) -> String {
        bundleURL.appending(path: "Contents/MacOS/clipdeck-mcp").path
    }

    /// 중앙 스킬 관리 도구로 세 클라이언트에 한 번에 등록하는 명령
    public static func command(executablePath: String) -> String {
        "skillshare mcp add clipdeck --target claude --target codex --target antigravity -- \"\(executablePath)\""
    }
}

public struct ItemCountSummary: Equatable, Sendable {
    public var total: Int
    public var mcpVisible: Int
    public init(total: Int, mcpVisible: Int) {
        self.total = total
        self.mcpVisible = mcpVisible
    }
}

extension ClipStore {
    /// 전체 항목 수와 MCP에 보이는(`mcp_hidden = 0`) 항목 수
    public func itemCountSummary() throws -> ItemCountSummary {
        let row = try db.query("SELECT COUNT(*) AS n, COALESCE(SUM(mcp_hidden = 0), 0) AS v FROM items").first
        func int(_ key: String) -> Int { if case .int(let n)? = row?[key] { Int(n) } else { 0 } }
        return ItemCountSummary(total: int("n"), mcpVisible: int("v"))
    }
}
