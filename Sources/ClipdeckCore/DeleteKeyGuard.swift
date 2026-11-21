import Foundation

/// 패널에서 ⌫를 항목 삭제(보드 탭이면 보드에서 빼기)로 볼지 정한다.
/// 검색어를 ⌫ 길게 눌러 지우다가 검색어가 비는 순간부터 항목이 확인 없이 연달아 지워지는 것을 막는다.
public enum DeleteKeyGuard {
    /// 검색어가 비워진 뒤 이 시간 안의 ⌫는 항목 삭제로 보지 않는다(막 다 지운 직후 한 번 더 누름 보호)
    public static let afterClearMs = 500

    /// - Parameters:
    ///   - isRepeat: 키를 누르고 있어 생긴 반복 입력인지
    ///   - queryEmpty: 검색어가 비었는지(검색어가 있으면 글자 삭제가 우선)
    ///   - msSinceQueryCleared: 검색어가 비워진 뒤 지난 시간. 이번에 연 뒤 비운 적이 없으면 nil
    public static func allowsItemDelete(isRepeat: Bool, queryEmpty: Bool, msSinceQueryCleared: Int?) -> Bool {
        guard queryEmpty, !isRepeat else { return false }
        if let ms = msSinceQueryCleared, ms < afterClearMs { return false }
        return true
    }
}
