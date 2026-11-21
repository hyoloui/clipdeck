import Foundation
import Testing
@testable import ClipdeckCore

@Suite struct DeleteKeyGuardTests {
    @Test func firstPressOnEmptyQueryDeletes() {
        #expect(DeleteKeyGuard.allowsItemDelete(isRepeat: false, queryEmpty: true, msSinceQueryCleared: nil))
        #expect(DeleteKeyGuard.allowsItemDelete(isRepeat: false, queryEmpty: true, msSinceQueryCleared: 500))
    }

    @Test func repeatNeverDeletes() {
        #expect(!DeleteKeyGuard.allowsItemDelete(isRepeat: true, queryEmpty: true, msSinceQueryCleared: nil))
        #expect(!DeleteKeyGuard.allowsItemDelete(isRepeat: true, queryEmpty: true, msSinceQueryCleared: 10_000))
    }

    @Test func queryTextIsDeletedFirst() {
        #expect(!DeleteKeyGuard.allowsItemDelete(isRepeat: false, queryEmpty: false, msSinceQueryCleared: nil))
    }

    /// 검색어를 막 다 지운 직후(0.5초 안)의 한 번 더 누름은 항목 삭제로 보지 않는다
    @Test func pressRightAfterClearingIsIgnored() {
        #expect(!DeleteKeyGuard.allowsItemDelete(isRepeat: false, queryEmpty: true, msSinceQueryCleared: 0))
        #expect(!DeleteKeyGuard.allowsItemDelete(isRepeat: false, queryEmpty: true, msSinceQueryCleared: 499))
    }
}
