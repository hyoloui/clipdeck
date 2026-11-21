import AppKit
import ClipdeckCore
import SwiftUI

extension PanelController {
    // MARK: ⌘P 보드 메뉴

    func showBoardMenu() {
        guard let item = model.selectedItem, let host = hosting else { return }
        let boards: [Pinboard]
        do {
            boards = try store.pinboards()
        } catch {
            Self.log.error("보드 목록 읽기 실패: \(String(describing: error), privacy: .public)")
            boards = []
        }
        let menu = NSMenu(title: "보드에 고정")
        if boards.isEmpty {
            menu.addItem(menuItem("새 보드 만들기…", tag: -1))
        } else {
            for b in boards { menu.addItem(menuItem(b.name, tag: Int(b.id))) }
            menu.addItem(.separator())
            menu.addItem(menuItem("새 보드 만들기…", tag: -1))
        }
        let row = presence.selectedRowFrame
        // 선택 행 아래쪽, 목록 안쪽에 띄운다(호스팅 뷰는 위가 원점)
        let point = NSPoint(x: row.minX + Layout.s24, y: row.maxY)
        menuOpen = true
        pendingItemID = item.id
        menu.popUp(positioning: nil, at: host.isFlipped ? point : NSPoint(x: point.x, y: host.bounds.height - point.y), in: host)
        menuOpen = false
        // 메뉴가 닫힌 뒤 패널이 키 창이 아니면(예: 바깥 클릭) 닫는다. 시트가 떠 있으면 그대로 둔다.
        if !sheetOpen, panel?.isKeyWindow == false { hide() }
    }

    func menuItem(_ title: String, tag: Int) -> NSMenuItem {
        let mi = NSMenuItem(title: title, action: #selector(boardPicked(_:)), keyEquivalent: "")
        mi.target = self
        mi.tag = tag
        return mi
    }

    @objc func boardPicked(_ sender: NSMenuItem) {
        guard let itemID = pendingItemID else { return }
        if sender.tag == -1 {
            promptNewBoard(for: itemID)
        } else {
            addToBoard(itemID: itemID, boardID: Int64(sender.tag))
        }
    }

    func addToBoard(itemID: Int64, boardID: Int64) {
        do {
            try store.add(itemID: itemID, toPinboard: boardID)
            model.reload()
        } catch {
            Self.log.error("보드 추가 실패: \(String(describing: error), privacy: .public)")
        }
    }

    /// `itemID`가 있으면 만든 보드에 그 항목도 넣는다. 이름이 비었거나 중복이면 오류 문구와 함께 시트를 다시 연다.
    func promptNewBoard(for itemID: Int64?, preset: String = "", error: String? = nil) {
        guard let panel else { return }
        let alert = NSAlert()
        alert.messageText = "새 보드 만들기"
        alert.informativeText = error ?? "보드 이름을 입력하세요."
        let field = NSTextField(string: preset)
        field.frame = NSRect(x: 0, y: 0, width: 240, height: Layout.s24)
        field.setAccessibilityLabel("보드 이름")
        alert.accessoryView = field
        alert.window.initialFirstResponder = field
        alert.addButton(withTitle: "만들기")
        alert.addButton(withTitle: "취소")
        sheetOpen = true
        alert.beginSheetModal(for: panel) { [weak self] response in
            MainActor.assumeIsolated {
                guard let self else { return }
                if response == .alertFirstButtonReturn {
                    do {
                        let id = try self.store.createPinboard(name: field.stringValue, color: nil)
                        if let itemID { self.addToBoard(itemID: itemID, boardID: id) } else { self.model.reload() }
                    } catch {
                        let message = (error as? PinboardError) == .duplicateName ? "같은 이름의 보드가 이미 있습니다."
                            : (error as? PinboardError) == .emptyName ? "보드 이름이 비어 있습니다."
                            : "보드를 만들지 못했습니다."
                        Self.log.error("보드 만들기 실패: \(String(describing: error), privacy: .public)")
                        // 시트는 닫히고 오류 문구와 함께 바로 다시 열린다(sheetOpen은 유지)
                        let preset = field.stringValue
                        DispatchQueue.main.async { [weak self] in
                            self?.promptNewBoard(for: itemID, preset: preset, error: message)
                        }
                        return
                    }
                }
                self.sheetOpen = false
                panel.makeKeyAndOrderFront(nil)
                self.focusSearchField()
            }
        }
    }
}
