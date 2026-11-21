import ClipdeckCore

extension PanelController {
    // MARK: 동작

    func paste(_ item: ClipItem, plainText: Bool) {
        // 앞 앱으로 포커스를 돌려야 하므로 패널을 먼저 닫는다
        hide(animated: false)
        onPaste?(item.id, plainText)
    }

    func copyOnly(_ item: ClipItem) {
        hide(animated: false)
        onCopyOnly?(item.id)
    }

    func deleteSelected() {
        guard let item = model.selectedItem else { return }
        do {
            if model.boardIndex > 0 {
                // 보드 탭에서는 그 보드에서만 뺀다(기록에는 남는다)
                try store.remove(itemID: item.id, fromPinboard: model.boards[model.boardIndex - 1].id)
            } else {
                try store.delete(id: item.id)
            }
            model.reload()
        } catch {
            Self.log.error("항목 삭제 실패: \(String(describing: error), privacy: .public)")
        }
    }

    func toggleMCPHidden() {
        guard let item = model.selectedItem else { return }
        do {
            try store.setMCPHidden(id: item.id, !item.mcpHidden)
            presence.revealedItemID = nil
            model.reload()
        } catch {
            Self.log.error("MCP 숨김 전환 실패: \(String(describing: error), privacy: .public)")
        }
    }
}
