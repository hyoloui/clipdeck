import Foundation

public enum KindClassifier {
    /// 순서: fileURL → (일반 텍스트가 없을 때만) png/tiff → color → link → text. 해당 없으면 nil.
    /// 텍스트와 이미지가 함께 오는 복사(스프레드시트 셀)는 텍스트로 본다. 표현은 전부 보관하므로 붙여넣기에는 이미지도 간다.
    public static func classify(utis: [String], plainText: String?) -> ItemKind? {
        if utis.contains(PasteboardTypes.fileURL) { return .file }
        let text = hasPlainText(plainText) ? plainText : nil
        if text == nil, utis.contains(PasteboardTypes.png) || utis.contains(PasteboardTypes.tiff) { return .image }
        if utis.contains(PasteboardTypes.color) { return .color }
        guard let text else { return nil }
        return isWebURL(text) ? .link : .text
    }

    /// "일반 텍스트가 있다"의 기준: 공백을 뺀 내용이 있는 텍스트. 종류 분류와 일반 텍스트 붙여넣기가 같이 쓴다.
    public static func hasPlainText(_ text: String?) -> Bool {
        guard let text else { return false }
        return !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
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
