import ClipdeckCore
import ClipdeckMCPKit
import Foundation

// stdout은 프로토콜 전용이다. 진단은 stderr로만 쓴다(print 금지).
signal(SIGPIPE, SIG_IGN)

/// stderr 쓰기 실패는 무시한다.
func log(_ message: String) {
    try? FileHandle.standardError.write(contentsOf: Data((message + "\n").utf8))
}

/// 읽는 쪽이 닫혀 stdout 쓰기가 실패하면(EPIPE 등) 더 보낼 곳이 없으므로 조용히 정상 종료한다.
func writeLine(_ line: String) {
    do { try FileHandle.standardOutput.write(contentsOf: Data((line + "\n").utf8)) } catch { exit(0) }
}

let store: ClipStore
do {
    store = try ClipStore(directory: ClipStore.defaultDirectory())
} catch {
    log("clipdeck-mcp: 저장소를 열 수 없습니다: \(error)")
    exit(1)
}

let notifyChange: () -> Void = {
    CFNotificationCenterPostNotification(CFNotificationCenterGetDarwinNotifyCenter(),
                                         CFNotificationName("local.hyoloui.clipdeck.db-changed" as CFString),
                                         nil, nil, true)
}
let server = JSONRPCServer(tools: ToolRegistry(store: store, clipboard: SystemClipboard(), notifyChange: notifyChange),
                           version: ClipdeckVersion.current)

func respond(_ line: Line, _ server: JSONRPCServer) {
    switch line {
    case .text(let text): if let response = server.handle(line: text) { writeLine(response) }
    case .invalidUTF8: writeLine(server.parseErrorResponse())
    case .tooLong: writeLine(server.oversizedLineResponse())
    }
}

var splitter = LineSplitter()
var chunk = [UInt8](repeating: 0, count: 64 * 1024)
while true {
    let n = read(STDIN_FILENO, &chunk, chunk.count)
    if n < 0 {
        if errno == EINTR { continue }
        log("clipdeck-mcp: stdin 읽기 실패 (errno \(errno))")
        exit(1)
    }
    if n == 0 { break }
    for line in splitter.feed(Data(chunk[0..<n])) { respond(line, server) }
}
if let last = splitter.finish() { respond(last, server) }
exit(0)
