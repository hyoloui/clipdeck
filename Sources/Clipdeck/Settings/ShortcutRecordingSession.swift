import AppKit
import SwiftUI

private struct KeyEventBox: @unchecked Sendable { let event: NSEvent? }

/// 단축키 녹화 상태를 한곳에서 관리한다. 한 번에 녹화기 하나만 켜지고(모니터도 하나),
/// 설정 창 밖 이벤트는 건드리지 않으며, 녹화 중에는 전역 단축키 등록을 푼다.
/// (CLT 환경에서는 `@State` 매크로를 쓸 수 없어 `ObservableObject`로 둔다.)
@MainActor
final class ShortcutRecordingSession: ObservableObject {
    /// 지금 녹화 중인 녹화기의 id
    @Published private(set) var activeID: String?
    /// 녹화기별 거부 사유
    @Published private(set) var messages: [String: String] = [:]

    /// 녹화를 받을 설정 창. 이 창의 키 입력만 처리한다.
    var window: () -> NSWindow? = { nil }
    /// 녹화 시작(true)·끝(false) 알림. 전역 단축키 등록을 풀고 되살리는 데 쓴다.
    var onRecordingChange: ((Bool) -> Void)?

    private var monitor: Any?
    private var onRecord: ((UInt16, UInt) -> String?)?

    func toggle(id: String, onRecord: @escaping (UInt16, UInt) -> String?) {
        let wasActive = activeID == id
        cancel()
        guard !wasActive else { return }
        messages[id] = nil
        activeID = id
        self.onRecord = onRecord
        onRecordingChange?(true)
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            let box = KeyEventBox(event: event)
            let consumed = MainActor.assumeIsolated { self?.handle(box.event!) ?? false }
            return consumed ? nil : box.event
        }
    }

    /// 녹화 중이 아니면 아무것도 하지 않는다
    func cancel() {
        guard activeID != nil else { return }
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        activeID = nil
        onRecord = nil
        onRecordingChange?(false)
    }

    /// 이벤트를 먹었으면 true
    private func handle(_ event: NSEvent) -> Bool {
        guard let id = activeID, let onRecord, event.window != nil, event.window === window() else { return false }
        let mods = event.modifierFlags.intersection([.shift, .control, .option, .command]).rawValue
        cancel() // 전역 단축키를 먼저 되살린 뒤 값을 넘긴다(새 값 등록은 그 위에서 바뀐다)
        if mods == 0, event.keyCode == 53 || event.keyCode == 51 { return true } // Esc 취소, ⌫ 변경 없음
        messages[id] = onRecord(event.keyCode, mods)
        return true
    }
}
