import Foundation

/// 클립보드에 쓸 표현 목록을 만든다.
public enum PastePayload {
    /// 항상 `selfMarker`(빈 Data)를 덧붙여 우리가 쓴 내용이 다시 캡처되지 않게 한다.
    /// `plainTextOnly`면 `public.utf8-plain-text`만 남긴다. 텍스트가 없으면 원본 그대로다.
    public static func build(_ reps: [Representation], plainTextOnly: Bool) -> [Representation] {
        var out = reps
        if plainTextOnly {
            let text = reps.filter { $0.uti == PasteboardTypes.plainText }
            if !text.isEmpty { out = text }
        }
        out.append(Representation(uti: PasteboardTypes.selfMarker, data: Data()))
        return out
    }
}
