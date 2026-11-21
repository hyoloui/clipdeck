import ClipdeckCore
import ClipdeckMCPKit
import Foundation

// stdout은 프로토콜 전용이다. 진단은 stderr로만 쓴다(print 금지).
signal(SIGPIPE, SIG_IGN)

func log(_ message: String) {
    FileHandle.standardError.write(Data((message + "\n").utf8))
}

func writeLine(_ line: String) {
    FileHandle.standardOutput.write(Data((line + "\n").utf8))
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

// 줄 단위로 읽는다. 상한을 넘는 줄은 메모리에 쌓지 않고 개행까지 버린 뒤 오류 응답을 쓴다.
var buffer = Data()
var discarding = false
var chunk = [UInt8](repeating: 0, count: 64 * 1024)
let newline = UInt8(ascii: "\n")

func process(_ lineData: Data, _ server: JSONRPCServer) {
    guard let line = String(data: lineData, encoding: .utf8) else {
        writeLine(server.handle(line: "\u{0}") ?? "")  // 잘못된 UTF-8도 -32700으로 응답한다.
        return
    }
    if let response = server.handle(line: line) { writeLine(response) }
}

while true {
    let n = read(STDIN_FILENO, &chunk, chunk.count)
    if n < 0 {
        if errno == EINTR { continue }
        log("clipdeck-mcp: stdin 읽기 실패 (errno \(errno))")
        exit(1)
    }
    if n == 0 { break }
    var start = 0
    for i in 0..<n where chunk[i] == newline {
        if discarding {
            discarding = false
            writeLine(server.oversizedLineResponse())
        } else {
            buffer.append(contentsOf: chunk[start..<i])
            process(buffer, server)
        }
        buffer.removeAll(keepingCapacity: true)
        start = i + 1
    }
    if !discarding {
        buffer.append(contentsOf: chunk[start..<n])
        if buffer.count > JSONRPCServer.maxLineBytes {
            discarding = true
            buffer = Data()
        }
    }
}
// EOF: 개행 없이 끝난 마지막 줄도 처리한다.
if !discarding, !buffer.isEmpty { process(buffer, server) }
exit(0)
