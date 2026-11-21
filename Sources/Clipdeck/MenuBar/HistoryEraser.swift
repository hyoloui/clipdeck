import AppKit
import ClipdeckCore
import os

/// "기록 전체 삭제…" 확인 창과 삭제. 메뉴바와 설정의 기록 탭이 함께 쓴다.
@MainActor
enum HistoryEraser {
    private static let log = Logger(subsystem: "local.hyoloui.clipdeck", category: "menubar")

    static func confirmAndErase(store: ClipStore) {
        let alert = NSAlert()
        alert.messageText = "클립보드 기록을 모두 지울까요?"
        alert.informativeText = "Pinboard에 넣은 항목은 지워지지 않습니다. 이 작업은 되돌릴 수 없습니다."
        alert.addButton(withTitle: "지우기")
        alert.addButton(withTitle: "취소")
        NSApp.activate()
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        do {
            try store.eraseHistory()
        } catch {
            log.error("기록 삭제 실패: \(String(describing: error), privacy: .public)")
            let failure = NSAlert()
            failure.messageText = "기록을 지우지 못했습니다"
            failure.informativeText = String(describing: error)
            failure.runModal()
        }
    }
}
