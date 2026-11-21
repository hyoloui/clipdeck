import AppKit
import ClipdeckCore
import SwiftUI

/// NSEvent를 isolation 경계 너머로 옮기기 위한 상자(항상 메인 스레드에서만 쓴다)
private struct EventBox: @unchecked Sendable { let event: NSEvent? }

extension PanelController {
    // MARK: 입력 감시

    func installMonitors() {
        removeMonitors()
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            // 로컬 모니터는 메인 스레드에서 불린다. NSEvent는 Sendable이 아니라 상자에 담아 넘긴다.
            let input = EventBox(event: event)
            return MainActor.assumeIsolated { EventBox(event: self.map { $0.handle(input.event!) } ?? input.event) }.event
        }
        // 패널 밖 클릭(다른 앱 포함)은 닫는다
        clickMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, !self.isPresentingModal else { return }
                self.hide()
            }
        }
    }

    func removeMonitors() {
        if let keyMonitor { NSEvent.removeMonitor(keyMonitor) }
        if let clickMonitor { NSEvent.removeMonitor(clickMonitor) }
        keyMonitor = nil
        clickMonitor = nil
    }

    static let digitKeyCodes: [UInt16: Int] = [18: 1, 19: 2, 20: 3, 21: 4, 23: 5, 22: 6, 26: 7, 28: 8, 25: 9]

    func matches(_ chord: KeyChord, _ event: NSEvent, flags: NSEvent.ModifierFlags) -> Bool {
        event.keyCode == chord.keyCode && flags.rawValue == chord.modifiers
    }

    /// nil을 돌려주면 이벤트를 먹은 것이다
    func handle(_ event: NSEvent) -> NSEvent? {
        guard let panel else { return event }
        let flags = event.modifierFlags.intersection([.shift, .control, .option, .command])
        // 보드 이름 시트(별도 창)의 입력란에도 편집 단축키를 적용한다
        if let sheet = panel.attachedSheet, event.window === sheet {
            // 메인 메뉴로 넘어가면 앱이 종료되거나 다른 창이 닫힐 수 있다: ⌘Q 무시, ⌘W는 시트 취소
            if flags == .command, event.keyCode == 12 { return nil }
            if flags == .command, event.keyCode == 13 {
                panel.endSheet(sheet, returnCode: .alertSecondButtonReturn)
                return nil
            }
            return performEdit(event, flags, sheet.firstResponder as? NSTextView) ? nil : event
        }
        guard event.window === panel else { return event }
        let editor = panel.firstResponder as? NSTextView
        // 한글 등 조합 중: ↩·↑↓·Tab류는 조합을 확정하고 같은 입력으로 바로 처리하고, 나머지(Esc·⌫ 등)는 입력기에 넘긴다
        if let editor, editor.hasMarkedText() {
            let commitKeys: Set<UInt16> = [36, 76, 125, 126, 48, keys.plainText.keyCode, keys.nextBoard.keyCode, keys.previousBoard.keyCode]
            guard commitKeys.contains(event.keyCode) else { return event }
            editor.unmarkText()
            // 입력기 쪽 조합 상태도 버려, 다음 자모에서 직전 음절이 중복 입력되지 않게 한다
            editor.inputContext?.discardMarkedText()
        }

        if matches(keys.plainText, event, flags: flags), let item = model.selectedItem {
            paste(item, plainText: true); return nil
        }
        if matches(keys.nextBoard, event, flags: flags) { model.selectNextBoard(); return nil }
        if matches(keys.previousBoard, event, flags: flags) { model.selectPreviousBoard(); return nil }

        switch (event.keyCode, flags) {
        case (53, []): // esc
            hide(); return nil
        case (126, []): model.moveSelection(-1); return nil
        case (125, []): model.moveSelection(1); return nil
        case (36, []), (76, []): // ↩, 키패드 엔터
            if let item = model.selectedItem { paste(item, plainText: false) }
            return nil
        case (51, []): // ⌫: 검색어가 있으면 글자 삭제가 우선
            guard model.query.isEmpty else { return event }
            // 누르고 있는 반복 입력이나 검색어를 막 다 지운 직후의 입력은 항목을 지우지 않는다
            let sinceCleared = model.queryClearedAt.map { Int(Date().timeIntervalSince($0) * 1000) }
            if DeleteKeyGuard.allowsItemDelete(isRepeat: event.isARepeat, queryEmpty: true,
                                               msSinceQueryCleared: sinceCleared) {
                deleteSelected()
            }
            return nil
        case (9, .command), (0, .command), (7, .command), (6, .command), (6, [.command, .shift]):
            return performEdit(event, flags, editor) ? nil : event
        case (13, .command): // ⌘W: 메인 메뉴로 넘어가 다른 창을 닫지 않게 esc와 같게 처리
            hide(); return nil
        case (12, .command): // ⌘Q: 패널에서 실수로 앱이 종료되지 않게 무시
            return nil
        case (43, .command): // ⌘, 설정 열기
            hide(animated: false)
            onOpenSettings?()
            return nil
        case (35, .command): // ⌘P
            DispatchQueue.main.async { [weak self] in self?.showBoardMenu() }
            return nil
        case (8, .command): // ⌘C: 검색창에 선택한 글자가 있으면 그 복사가 우선
            if let editor, editor.selectedRange().length > 0 { editor.copy(nil); return nil }
            if let item = model.selectedItem { copyOnly(item) }
            return nil
        case (4, .command): // ⌘H: 항목별 MCP 숨김 전환
            toggleMCPHidden(); return nil
        case (15, .command): // ⌘R: 가려진 항목 미리보기 열기/닫기
            if let item = model.selectedItem, item.mcpHidden {
                presence.revealedItemID = presence.revealedItemID == item.id ? nil : item.id
            }
            return nil
        default:
            if flags == .command, let n = Self.digitKeyCodes[event.keyCode] {
                if let item = model.item(atShortcut: n) { paste(item, plainText: false) }
                return nil
            }
            return event
        }
    }

    /// 입력란 편집 단축키(⌘V·⌘A·⌘X·⌘C·⌘Z·⇧⌘Z). 앱이 비활성이라 메뉴 단축키가 오지 않으므로 직접 보낸다.
    /// 처리했으면 true. 편집기가 없으면 false.
    func performEdit(_ event: NSEvent, _ flags: NSEvent.ModifierFlags, _ editor: NSTextView?) -> Bool {
        guard let editor else { return false }
        switch (event.keyCode, flags) {
        case (9, .command): editor.paste(nil)
        case (0, .command): editor.selectAll(nil)
        case (7, .command): editor.cut(nil)
        case (8, .command): editor.copy(nil)
        case (6, .command): NSApp.sendAction(Selector(("undo:")), to: nil, from: nil)
        case (6, [.command, .shift]): NSApp.sendAction(Selector(("redo:")), to: nil, from: nil)
        default: return false
        }
        return true
    }
}
