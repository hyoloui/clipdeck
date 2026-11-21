import ClipdeckCore
import CoreGraphics
import Foundation
import ImageIO
@testable import ClipdeckMCPKit

/// 임시 폴더에 새 ClipStore를 만든다. 호출부가 `defer`로 폴더를 지운다.
func makeTempStore() throws -> (ClipStore, URL) {
    let dir = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
    return (try ClipStore(directory: dir), dir)
}

func textClip(_ s: String, app: String? = nil, hidden: Bool = false) -> NewClip {
    NewClip(kind: .text, preview: s, plainText: s, contentHash: "hash-" + s,
            sourceAppBundleID: app, sourceAppName: app, mcpHidden: hidden,
            representations: [Representation(uti: "public.utf8-plain-text", data: Data(s.utf8))])
}

/// 항목을 넣고 id를 돌려준다.
@discardableResult
func insertText(_ store: ClipStore, _ s: String, hidden: Bool = false, now: Date = .now) throws -> Int64 {
    switch try store.insert(textClip(s, app: "com.example.app", hidden: hidden), now: now) {
    case .inserted(let id), .bumped(let id): id
    }
}

/// 단색 PNG
func makePNG(width: Int, height: Int) -> Data {
    let ctx = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                        space: CGColorSpaceCreateDeviceRGB(),
                        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    ctx.setFillColor(red: 0.2, green: 0.4, blue: 0.8, alpha: 1)
    ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))
    let out = NSMutableData()
    let dest = CGImageDestinationCreateWithData(out, "public.png" as CFString, 1, nil)!
    CGImageDestinationAddImage(dest, ctx.makeImage()!, nil)
    CGImageDestinationFinalize(dest)
    return out as Data
}

func pngSize(_ data: Data) -> (Int, Int)? {
    guard let src = CGImageSourceCreateWithData(data as CFData, nil),
          let p = CGImageSourceCopyPropertiesAtIndex(src, 0, nil) as? [CFString: Any],
          let w = p[kCGImagePropertyPixelWidth] as? Int, let h = p[kCGImagePropertyPixelHeight] as? Int else { return nil }
    return (w, h)
}

/// 쓴 내용을 기록하는 가짜 클립보드
final class FakeClipboard: ClipboardWriting {
    nonisolated(unsafe) var writes: [[Representation]] = []
    func write(_ representations: [Representation]) { writes.append(representations) }
}

final class ChangeCounter {
    nonisolated(unsafe) var count = 0
}

func makeRegistry(_ store: ClipStore, clipboard: FakeClipboard = FakeClipboard(),
                  counter: ChangeCounter = ChangeCounter()) -> ToolRegistry {
    ToolRegistry(store: store, clipboard: clipboard, notifyChange: { counter.count += 1 })
}

/// 결과의 텍스트 콘텐츠를 이어 붙인다.
func text(_ r: ToolResult) -> String {
    r.content.compactMap { if case .text(let s) = $0 { s } else { nil } }.joined(separator: "\n")
}

/// 목록 도구 결과에서 id 배열을 뽑는다.
func ids(_ r: ToolResult) -> [Int64] {
    guard let data = text(r).data(using: .utf8),
          case .array(let items)? = try? JSONDecoder().decode(JSONValue.self, from: data) else { return [] }
    return items.compactMap { if case .object(let o) = $0 { o["id"]?.intValue } else { nil } }
}

/// 캡처 경로처럼 NewClip을 그대로 넣고 id를 돌려준다.
func insertClip(_ store: ClipStore, _ clip: NewClip) throws -> Int64 {
    switch try store.insert(clip) {
    case .inserted(let id), .bumped(let id): id
    }
}
