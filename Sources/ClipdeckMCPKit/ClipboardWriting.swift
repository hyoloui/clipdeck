import AppKit
import ClipdeckCore

public protocol ClipboardWriting {
    func write(_ representations: [Representation])
}

/// 받은 표현을 그대로 쓴다(자체 쓰기 표시는 호출부가 `ClipboardPayload`로 붙인다).
public enum ClipboardPayload {
    /// 자체 쓰기 표시(`selfMarker`)를 정확히 한 번 덧붙인다. 앱 감시기가 이 표시를 보면 저장하지 않으므로,
    /// MCP가 복사한 텍스트가 기록에 남아 숨김 항목의 존재를 드러내는 일이 없다.
    public static func withSelfMarker(_ reps: [Representation]) -> [Representation] {
        if reps.contains(where: { $0.uti == PasteboardTypes.selfMarker }) { return reps }
        return reps + [Representation(uti: PasteboardTypes.selfMarker, data: PasteboardTypes.selfMarkerData)]
    }
}

public struct SystemClipboard: ClipboardWriting {
    let pasteboard: NSPasteboard
    public init(pasteboard: NSPasteboard = .general) { self.pasteboard = pasteboard }

    public func write(_ representations: [Representation]) {
        let files = representations.filter { $0.uti == PasteboardTypes.fileURL }
        let others = representations.filter { $0.uti != PasteboardTypes.fileURL }

        func item(_ reps: [Representation]) -> NSPasteboardItem {
            let item = NSPasteboardItem()
            for rep in reps { item.setData(rep.data, forType: NSPasteboard.PasteboardType(rep.uti)) }
            return item
        }

        // 파일이 여럿이면 파일마다 항목을 따로 만든다. 파일 외 표현(자체 쓰기 표시 포함)은 첫 항목에 둔다.
        var items: [NSPasteboardItem]
        if files.count > 1 {
            items = files.map { item([$0]) }
            for rep in others { items[0].setData(rep.data, forType: NSPasteboard.PasteboardType(rep.uti)) }
        } else {
            items = [item(representations)]
        }

        let pb = pasteboard
        pb.clearContents()
        pb.writeObjects(items)
    }
}
