import Foundation

public enum KindClassifier {
    /// 순서: fileURL → png/tiff → color → link → text. 해당 없으면 nil.
    public static func classify(utis: [String], plainText: String?) -> ItemKind? {
        if utis.contains(PasteboardTypes.fileURL) { return .file }
        if utis.contains(PasteboardTypes.png) || utis.contains(PasteboardTypes.tiff) { return .image }
        if utis.contains(PasteboardTypes.color) { return .color }
        guard let text = plainText,
              !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        return isWebURL(text) ? .link : .text
    }

    /// 텍스트 전체(앞뒤 공백 제외)가 http/https URL 하나인지
    private static func isWebURL(_ text: String) -> Bool {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard t.rangeOfCharacter(from: .whitespacesAndNewlines) == nil,
              let url = URL(string: t),
              let scheme = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https",
              let host = url.host, !host.isEmpty else { return false }
        return true
    }
}
