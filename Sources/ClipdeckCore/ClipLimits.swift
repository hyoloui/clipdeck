import Foundation

/// 텍스트 크기 상한. MCP에 닿는 텍스트(`items.plain_text`, FTS)와 비밀값 검사 범위를 같게 맞춘다.
public enum ClipLimits {
    /// `items.plain_text`에 담는 최대 크기(UTF-8 바이트). 비밀값 검사·MCP `get_item`·`create_text_item` 상한도 이 값이다.
    public static let plainTextBytes = 102_400

    /// UTF-8로 `maxBytes`를 넘으면 그 안의 마지막 문자 경계에서 자른다.
    public static func prefix(_ s: String, maxBytes: Int = plainTextBytes) -> String {
        guard s.utf8.count > maxBytes else { return s }
        var i = s.utf8.index(s.utf8.startIndex, offsetBy: maxBytes)
        while i > s.startIndex, i.samePosition(in: s) == nil { i = s.utf8.index(before: i) }
        return String(s[..<i])
    }
}
