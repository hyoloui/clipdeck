import Foundation
@testable import ClipdeckCore

/// 임시 폴더에 새 ClipStore를 만든다.
func makeTempStore() throws -> (ClipStore, URL) {
    let dir = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
    return (try ClipStore(directory: dir), dir)
}

func textClip(_ s: String, app: String? = nil, hidden: Bool = false) -> NewClip {
    NewClip(kind: .text, preview: s, plainText: s, contentHash: "hash-" + s,
            sourceAppBundleID: app, sourceAppName: app, mcpHidden: hidden,
            representations: [Representation(uti: "public.utf8-plain-text", data: Data(s.utf8))])
}
