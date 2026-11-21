import AppKit
import ClipdeckCore
import Foundation
import Testing
@testable import ClipdeckMCPKit

/// 샌드박스에서는 pasteboard 서버에 닿지 않아 쓰기가 조용히 실패한다. 그럴 때는 이 테스트를 건너뛴다.
private let pasteboardAvailable: Bool = {
    let pb = NSPasteboard.withUniqueName()
    defer { pb.releaseGlobally() }
    pb.clearContents()
    pb.writeObjects(["probe" as NSString])
    return pb.pasteboardItems != nil
}()

@Suite struct ClipboardPayloadTests {
    @Test func addsExactlyOneMarkerKeepingOrder() {
        let reps = [Representation(uti: "public.utf8-plain-text", data: Data("a".utf8)),
                    Representation(uti: "public.rtf", data: Data("b".utf8))]
        let out = ClipboardPayload.withSelfMarker(reps)
        #expect(Array(out.prefix(2)) == reps)
        #expect(out.filter { $0.uti == PasteboardTypes.selfMarker }.count == 1)
        #expect(ClipboardPayload.withSelfMarker(out) == out)
        // 자체 쓰기 표시 데이터는 Core 한 곳의 정의를 쓴다(앱 붙여넣기와 같은 값)
        #expect(out.last == Representation(uti: PasteboardTypes.selfMarker, data: PasteboardTypes.selfMarkerData))
    }

    /// 시스템 클립보드가 아니라 이름 없는 임시 pasteboard에 쓴다.
    @Test(.enabled(if: pasteboardAvailable, "pasteboard 서버에 닿을 때만 실행"))
    func systemClipboardWritesMarkerOnFirstItem() throws {
        let pb = NSPasteboard.withUniqueName()
        defer { pb.releaseGlobally() }
        let files = ["file:///tmp/a.txt", "file:///tmp/b.txt"].map {
            Representation(uti: PasteboardTypes.fileURL, data: Data($0.utf8))
        }
        SystemClipboard(pasteboard: pb).write(ClipboardPayload.withSelfMarker(files))
        #expect(pb.pasteboardItems?.count == 2)
        #expect(pb.pasteboardItems?.first?.types.contains(NSPasteboard.PasteboardType(PasteboardTypes.selfMarker)) == true)
        #expect(pb.types?.contains(NSPasteboard.PasteboardType(PasteboardTypes.selfMarker)) == true)
    }
}
