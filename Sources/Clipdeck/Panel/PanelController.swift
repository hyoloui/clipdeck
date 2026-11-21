import AppKit
import ClipdeckCore
import SwiftUI
import os

/// NSEvent를 isolation 경계 너머로 옮기기 위한 상자(항상 메인 스레드에서만 쓴다)
private struct EventBox: @unchecked Sendable { let event: NSEvent? }

/// 키 입력을 받을 수 있지만 앞 앱을 활성 상태에서 끌어내리지 않는 패널
final class ClipPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

/// 패널을 한 번 만들어 재사용하고, 열고 닫기와 키 처리를 맡는다.
@MainActor
final class PanelController: NSObject {
    private static let log = Logger(subsystem: "local.hyoloui.clipdeck", category: "panel")

    /// 붙여넣기(다음 작업의 PasteService가 연결). nil이면 클립보드에 텍스트만 쓰고 닫는다.
    var onPaste: ((_ itemID: Int64, _ plainText: Bool) -> Void)?
    var onCopyOnly: ((_ itemID: Int64) -> Void)?
    /// 패널을 보이기 직전에 부른다(앞 앱 기억용)
    var onWillShow: (() -> Void)?
    /// ⌘, 로 설정 창을 연다(메뉴바 아이콘을 숨겼을 때의 진입로)
    var onOpenSettings: (() -> Void)?

    private let store: ClipStore
    private let settings: SettingsStore
    private let model: PanelModel
    private let presence = PanelPresence()
    private var panel: ClipPanel?
    private var hosting: NSHostingView<PanelView>?
    private var keyMonitor: Any?
    private var clickMonitor: Any?
    private var resignObserver: NSObjectProtocol?
    private var keys = PanelKeyBindings()
    /// 패널이 열려 있는(또는 열려는) 논리 상태. 페이드아웃 중에는 false다.
    private var isOpen = false
    /// 페이드아웃을 취소하기 위한 세대 번호
    private var hideToken = 0
    /// 메뉴·시트가 떠 있는 동안에는 포커스를 잃어도 닫지 않는다
    private var menuOpen = false
    private var sheetOpen = false
    private var isPresentingModal: Bool { menuOpen || sheetOpen }

    init(store: ClipStore, settings: SettingsStore) {
        self.store = store
        self.settings = settings
        self.model = PanelModel(store: store)
        super.init()
    }

    /// 시트가 떠 있는 동안에는 무시한다(시트가 붙은 채 닫히는 것 방지)
    func toggle() {
        if sheetOpen { return }
        isOpen ? hide() : show()
    }

    func show() {
        guard !isOpen else { return }
        isOpen = true
        hideToken += 1 // 페이드아웃 중이면 취소하고 바로 다시 나타난다
        onWillShow?()
        let panel = self.panel ?? makePanel()
        applySettings(settings.load())

        model.resetForShow()
        presence.apps = model.sourceApps()
        presence.revealedItemID = nil
        presence.generation += 1
        position(panel)

        // 숨겨져 있던 경우만 투명·축소 상태에서 시작해 스프링으로 등장시킨다(페이드 도중이면 현재 값에서 이어간다)
        if !panel.isVisible {
            presence.shown = false
            panel.alphaValue = 0
        }
        panel.makeKeyAndOrderFront(nil)
        focusSearchField()
        installMonitors()
        presence.shown = true
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.12
            panel.animator().alphaValue = 1
        }
    }

    /// 키 바인딩·푸터 힌트·화면 공유 중 숨김을 새 설정으로 바꾼다(패널이 열려 있어도 즉시 반영)
    func applySettings(_ s: AppSettings) {
        keys = s.panelKeys
        presence.plainTextHint = Self.plainTextHint(s.panelKeys.plainText)
        panel?.sharingType = s.hideDuringScreenSharing ? .none : .readOnly
    }

    /// 패널이 열려 있을 때만 목록을 다시 읽는다(MCP 서버 등 다른 프로세스가 DB를 바꿨을 때)
    func reloadIfOpen() {
        guard isOpen else { return }
        model.reload()
    }

    /// `animated`가 true면 120ms 페이드아웃 뒤 닫는다. 붙여넣기·복사 경로는 false로 즉시 닫는다.
    func hide(animated: Bool = true) {
        guard let panel, panel.isVisible else { return }
        if !isOpen { // 이미 페이드아웃 중
            if !animated { hideToken += 1; finishHide() }
            return
        }
        isOpen = false
        removeMonitors()
        hideToken += 1
        guard animated else { finishHide(); return }
        let token = hideToken
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.12
            panel.animator().alphaValue = 0
        }, completionHandler: { [weak self] in
            MainActor.assumeIsolated {
                guard let self, self.hideToken == token, !self.isOpen else { return }
                self.finishHide()
            }
        })
    }

    private func finishHide() {
        var t = Transaction(); t.disablesAnimations = true
        withTransaction(t) { presence.shown = false }
        panel?.orderOut(nil)
    }

    // MARK: 생성

    private func makePanel() -> ClipPanel {
        let panel = ClipPanel(contentRect: NSRect(x: 0, y: 0, width: Layout.panelWidth, height: Layout.panelHeight),
                              styleMask: [.nonactivatingPanel, .titled, .fullSizeContentView],
                              backing: .buffered, defer: false)
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        for b in [NSWindow.ButtonType.closeButton, .miniaturizeButton, .zoomButton] {
            panel.standardWindowButton(b)?.isHidden = true
        }
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.isReleasedWhenClosed = false
        panel.hidesOnDeactivate = false
        panel.isMovableByWindowBackground = false
        panel.setAccessibilityLabel("Clipdeck 검색 패널")

        let effect = NSVisualEffectView()
        effect.material = .hudWindow
        effect.blendingMode = .behindWindow
        effect.state = .active
        panel.contentView = effect

        let root = PanelView(model: model, presence: presence, loader: PreviewLoader(store: store),
                             onActivate: { [weak self] item in self?.paste(item, plainText: false) },
                             onNewBoard: { [weak self] in self?.promptNewBoard(for: nil) })
        let host = NSHostingView(rootView: root)
        host.sizingOptions = []
        host.safeAreaRegions = []
        host.frame = effect.bounds
        host.autoresizingMask = [.width, .height]
        effect.addSubview(host)
        hosting = host

        resignObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.didResignKeyNotification, object: panel, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, !self.isPresentingModal else { return }
                self.hide()
            }
        }
        self.panel = panel
        return panel
    }

    /// 마우스가 있는 화면의 중앙. 없으면 주 화면.
    private func position(_ panel: NSPanel) {
        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { $0.frame.contains(mouse) } ?? NSScreen.main ?? NSScreen.screens[0]
        let f = screen.visibleFrame
        panel.setFrameOrigin(NSPoint(x: (f.midX - Layout.panelWidth / 2).rounded(),
                                     y: (f.midY - Layout.panelHeight / 2).rounded()))
    }

    private func focusSearchField() {
        guard let panel, let field = Self.findSearchField(in: panel.contentView) else { return }
        panel.makeFirstResponder(field)
    }

    private static func findSearchField(in view: NSView?) -> PanelSearchField? {
        guard let view else { return nil }
        if let f = view as? PanelSearchField { return f }
        for sub in view.subviews { if let f = findSearchField(in: sub) { return f } }
        return nil
    }

    private static func plainTextHint(_ chord: KeyChord) -> String {
        ShortcutFormat.display(chord)
    }

    // MARK: 입력 감시

    private func installMonitors() {
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

    private func removeMonitors() {
        if let keyMonitor { NSEvent.removeMonitor(keyMonitor) }
        if let clickMonitor { NSEvent.removeMonitor(clickMonitor) }
        keyMonitor = nil
        clickMonitor = nil
    }

    private static let digitKeyCodes: [UInt16: Int] = [18: 1, 19: 2, 20: 3, 21: 4, 23: 5, 22: 6, 26: 7, 28: 8, 25: 9]

    private func matches(_ chord: KeyChord, _ event: NSEvent, flags: NSEvent.ModifierFlags) -> Bool {
        event.keyCode == chord.keyCode && flags.rawValue == chord.modifiers
    }

    /// nil을 돌려주면 이벤트를 먹은 것이다
    private func handle(_ event: NSEvent) -> NSEvent? {
        guard let panel else { return event }
        let flags = event.modifierFlags.intersection([.shift, .control, .option, .command])
        // 보드 이름 시트(별도 창)의 입력란에도 편집 단축키를 적용한다
        if let sheet = panel.attachedSheet, event.window === sheet {
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
            deleteSelected(); return nil
        case (9, .command), (0, .command), (7, .command), (6, .command), (6, [.command, .shift]):
            return performEdit(event, flags, editor) ? nil : event
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
    private func performEdit(_ event: NSEvent, _ flags: NSEvent.ModifierFlags, _ editor: NSTextView?) -> Bool {
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

    // MARK: 동작

    private func paste(_ item: ClipItem, plainText: Bool) {
        if let onPaste {
            // 앞 앱으로 포커스를 돌려야 하므로 패널을 먼저 닫는다
            hide(animated: false)
            onPaste(item.id, plainText)
        } else {
            fallbackCopy(item, plainText: plainText)
            hide(animated: false)
        }
    }

    private func copyOnly(_ item: ClipItem) {
        hide(animated: false)
        if let onCopyOnly {
            onCopyOnly(item.id)
        } else {
            fallbackCopy(item, plainText: true)
        }
    }

    /// PasteService가 연결되기 전의 임시 동작: 텍스트만 클립보드에 쓴다
    private func fallbackCopy(_ item: ClipItem, plainText: Bool) {
        guard let text = try? store.plainText(itemID: item.id) else { return }
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(text, forType: .string)
    }

    private func deleteSelected() {
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

    private func toggleMCPHidden() {
        guard let item = model.selectedItem else { return }
        do {
            try store.setMCPHidden(id: item.id, !item.mcpHidden)
            presence.revealedItemID = nil
            model.reload()
        } catch {
            Self.log.error("MCP 숨김 전환 실패: \(String(describing: error), privacy: .public)")
        }
    }

    // MARK: ⌘P 보드 메뉴

    private func showBoardMenu() {
        guard let item = model.selectedItem, let host = hosting else { return }
        let boards = (try? store.pinboards()) ?? []
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

    private var pendingItemID: Int64?

    private func menuItem(_ title: String, tag: Int) -> NSMenuItem {
        let mi = NSMenuItem(title: title, action: #selector(boardPicked(_:)), keyEquivalent: "")
        mi.target = self
        mi.tag = tag
        return mi
    }

    @objc private func boardPicked(_ sender: NSMenuItem) {
        guard let itemID = pendingItemID else { return }
        if sender.tag == -1 {
            promptNewBoard(for: itemID)
        } else {
            addToBoard(itemID: itemID, boardID: Int64(sender.tag))
        }
    }

    private func addToBoard(itemID: Int64, boardID: Int64) {
        do {
            try store.add(itemID: itemID, toPinboard: boardID)
            model.reload()
        } catch {
            Self.log.error("보드 추가 실패: \(String(describing: error), privacy: .public)")
        }
    }

    /// `itemID`가 있으면 만든 보드에 그 항목도 넣는다. 이름이 비었거나 중복이면 오류 문구와 함께 시트를 다시 연다.
    private func promptNewBoard(for itemID: Int64?, preset: String = "", error: String? = nil) {
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
