import AppKit
import ClipdeckCore

public protocol ClipboardWriting {
    func write(_ representations: [Representation])
}

/// 시스템 클립보드에 쓴다. `selfMarker`는 붙이지 않는다(MCP로 복사한 내용도 기록에 남게 하려고).
public struct SystemClipboard: ClipboardWriting {
    public init() {}

    public func write(_ representations: [Representation]) {
        let files = representations.filter { $0.uti == PasteboardTypes.fileURL }
        let others = representations.filter { $0.uti != PasteboardTypes.fileURL }

        func item(_ reps: [Representation]) -> NSPasteboardItem {
            let item = NSPasteboardItem()
            for rep in reps { item.setData(rep.data, forType: NSPasteboard.PasteboardType(rep.uti)) }
            return item
        }

        // 파일이 여럿이면 파일마다 항목을 따로 만든다. 하나면 다른 표현과 한 항목에 둔다.
        var items: [NSPasteboardItem] = []
        if files.count > 1 {
            items = files.map { item([$0]) }
            if !others.isEmpty { items.append(item(others)) }
        } else {
            items = [item(representations)]
        }

        let pb = NSPasteboard.general
        pb.clearContents()
        pb.writeObjects(items)
    }
}
