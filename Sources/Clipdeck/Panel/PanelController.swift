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
    /// 메뉴·시트가 떠 있는 동안에는 포커스를 잃어도 닫지 않는다
    private var isPresentingModal = false

    init(store: ClipStore, settings: SettingsStore) {
        self.store = store
        self.settings = settings
        self.model = PanelModel(store: store)
        super.init()
    }

    var isVisible: Bool { panel?.isVisible ?? false }

    func toggle() { isVisible ? hide() : show() }

    func show() {
        guard !isVisible else { return }
        onWillShow?()
        let s = settings.load()
        keys = s.panelKeys
        let panel = self.panel ?? makePanel()
        panel.sharingType = s.hideDuringScreenSharing ? .none : .readOnly

        model.resetForShow()
        presence.revealedItemID = nil
        presence.generation += 1
        position(panel)

        // 첫 프레임은 투명·축소 상태로 만들고 곧바로 스프링으로 등장시킨다
        presence.shown = false
        panel.alphaValue = 0
        panel.makeKeyAndOrderFront(nil)
        focusSearchField()
        installMonitors()
        presence.shown = true
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.12
            panel.animator().alphaValue = 1
        }
    }

    func hide() {
        guard let panel, panel.isVisible else { return }
        removeMonitors()
        // 퇴장은 지연 없이 즉시(붙여넣기 흐름이 이 뒤에 이어진다)
        var t = Transaction(); t.disablesAnimations = true
        withTransaction(t) { presence.shown = false }
        panel.orderOut(nil)
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
        panel.isMovableByWindowBackground = true
        panel.setAccessibilityLabel("Clipdeck 검색 패널")

        let effect = NSVisualEffectView()
        effect.material = .hudWindow
        effect.blendingMode = .behindWindow
        effect.state = .active
        panel.contentView = effect

        let root = PanelView(model: model, presence: presence, loader: PreviewLoader(store: store),
                             plainTextHint: Self.plainTextHint(keys.plainText),
                             onActivate: { [weak self] item in self?.paste(item, plainText: false) })
        let host = NSHostingView(rootView: root)
        host.sizingOptions = []
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
        chord == PanelKeyBindings().plainText ? "⇧↩" : "지정 키"
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
        guard let panel, event.window === panel else { return event }
        let flags = event.modifierFlags.intersection([.shift, .control, .option, .command])
        let editor = panel.firstResponder as? NSTextView
        // 한글 등 조합 중에는 ↩·방향키·Esc·⌫를 입력기에 넘긴다
        if editor?.hasMarkedText() == true { return event }

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
        case (35, .command): // ⌘P
            DispatchQueue.main.async { [weak self] in self?.showBoardMenu() }
            return nil
        case (8, .command): // ⌘C: 검색창에 선택한 글자가 있으면 그 복사가 우선
            if let editor, editor.selectedRange().length > 0 { return event }
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

    // MARK: 동작

    private func paste(_ item: ClipItem, plainText: Bool) {
        if let onPaste {
            onPaste(item.id, plainText)
        } else {
            fallbackCopy(item, plainText: plainText)
            hide()
        }
    }

    private func copyOnly(_ item: ClipItem) {
        if let onCopyOnly {
            onCopyOnly(item.id)
        } else {
            fallbackCopy(item, plainText: true)
        }
        hide()
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
            try store.delete(id: item.id)
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
        isPresentingModal = true
        pendingItemID = item.id
        menu.popUp(positioning: nil, at: host.isFlipped ? point : NSPoint(x: point.x, y: host.bounds.height - point.y), in: host)
        isPresentingModal = false
        // 메뉴가 닫힌 뒤 패널이 키 창이 아니면(예: 바깥 클릭) 닫는다
        if panel?.isKeyWindow == false, panel?.attachedSheet == nil { hide() }
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

    private func promptNewBoard(for itemID: Int64) {
        guard let panel else { return }
        let alert = NSAlert()
        alert.messageText = "새 보드 만들기"
        alert.informativeText = "보드 이름을 입력하세요."
        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 240, height: Layout.s24))
        field.setAccessibilityLabel("보드 이름")
        alert.accessoryView = field
        alert.window.initialFirstResponder = field
        alert.addButton(withTitle: "만들기")
        alert.addButton(withTitle: "취소")
        isPresentingModal = true
        alert.beginSheetModal(for: panel) { [weak self] response in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.isPresentingModal = false
                if response == .alertFirstButtonReturn {
                    do {
                        let id = try self.store.createPinboard(name: field.stringValue, color: nil)
                        self.addToBoard(itemID: itemID, boardID: id)
                    } catch {
                        Self.log.error("보드 만들기 실패: \(String(describing: error), privacy: .public)")
                    }
                }
                panel.makeKeyAndOrderFront(nil)
                self.focusSearchField()
            }
        }
    }
}
