import Foundation

public enum Line: Equatable, Sendable {
    case text(String)
    case invalidUTF8
    case tooLong
}

/// 바이트 청크를 개행 기준 줄로 나눈다. 상한을 넘는 줄은 메모리에 쌓지 않고 개행까지 버린 뒤 `.tooLong` 하나로 알린다.
public struct LineSplitter {
    private let maxLineBytes: Int
    private var buffer = Data()
    private var discarding = false

    public init(maxLineBytes: Int = 4 * 1024 * 1024) {
        self.maxLineBytes = maxLineBytes
    }

    public mutating func feed(_ chunk: Data) -> [Line] {
        var lines: [Line] = []
        var start = chunk.startIndex
        for i in chunk.indices where chunk[i] == UInt8(ascii: "\n") {
            if discarding {
                lines.append(.tooLong)
            } else {
                buffer.append(chunk[start..<i])
                lines.append(buffer.count > maxLineBytes ? .tooLong : Self.line(buffer))
            }
            discarding = false
            buffer.removeAll(keepingCapacity: true)
            start = i + 1
        }
        if !discarding {
            buffer.append(chunk[start...])
            if buffer.count > maxLineBytes {
                discarding = true
                buffer = Data()
            }
        }
        return lines
    }

    /// 입력이 끝났을 때 개행 없이 남은 마지막 줄을 돌려준다.
    public mutating func finish() -> Line? {
        defer { buffer = Data(); discarding = false }
        if discarding { return .tooLong }
        return buffer.isEmpty ? nil : Self.line(buffer)
    }

    private static func line(_ data: Data) -> Line {
        var data = data
        if data.last == UInt8(ascii: "\r") { data.removeLast() }
        guard let s = String(data: data, encoding: .utf8) else { return .invalidUTF8 }
        return .text(s)
    }
}
