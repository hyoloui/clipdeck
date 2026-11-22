import AppKit
import ClipdeckCore
import SwiftUI
import os

/// 키 입력을 받을 수 있지만 앞 앱을 활성 상태에서 끌어내리지 않는 패널
final class ClipPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
    /// 빈 영역 드래그가 끝났을 때(마우스 업) 부른다
    var onDragEnd: (() -> Void)?
}

/// 패널을 한 번 만들어 재사용하고, 열고 닫기와 키 처리를 맡는다.
@MainActor
final class PanelController: NSObject {
    static let log = Logger(subsystem: "local.hyoloui.clipdeck", category: "panel")

    /// 붙여넣기(PasteService가 연결한다)
    var onPaste: ((_ itemID: Int64, _ plainText: Bool) -> Void)?
    var onCopyOnly: ((_ itemID: Int64) -> Void)?
    /// 패널을 보이기 직전에 부른다(앞 앱 기억용)
    var onWillShow: (() -> Void)?
    /// ⌘, 로 설정 창을 연다(메뉴바 아이콘을 숨겼을 때의 진입로)
    var onOpenSettings: (() -> Void)?

    let store: ClipStore
    let settings: SettingsStore
    let model: PanelModel
    let presence = PanelPresence()
    let previewLoader: PreviewLoader
    var panel: ClipPanel?
    var hosting: NSHostingView<PanelView>?
    var keyMonitor: Any?
    var clickMonitor: Any?
    var resignObserver: NSObjectProtocol?
    var keys = PanelKeyBindings()
    /// 패널이 열려 있는(또는 열려는) 논리 상태. 페이드아웃 중에는 false다.
    var isOpen = false
    /// 페이드아웃을 취소하기 위한 세대 번호
    var hideToken = 0
    /// 메뉴·시트가 떠 있는 동안에는 포커스를 잃어도 닫지 않는다
    var menuOpen = false
    var sheetOpen = false
    var pendingItemID: Int64?
    var isPresentingModal: Bool { menuOpen || sheetOpen }

    init(store: ClipStore, settings: SettingsStore) {
        self.store = store
        self.settings = settings
        self.model = PanelModel(store: store)
        self.previewLoader = PreviewLoader(store: store)
        super.init()
    }

    /// 앱 실행 시 패널을 미리 만들어 첫 단축키에서 만드는 시간을 없앤다
    func prepare() {
        if panel == nil { _ = makePanel() }
        applySettings(settings.load())
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
        presence.revealedItemID = nil
        presence.generation += 1
        position(panel)

        // 숨겨져 있던 경우만 투명·축소 상태에서 시작해 스프링으로 등장시킨다(페이드 도중이면 현재 값에서 이어간다)
        if !panel.isVisible {
            presence.shown = false
            panel.alphaValue = 0
        }
        panel.makeKeyAndOrderFront(nil)
        panel.invalidateShadow()
        focusSearchField()
        installMonitors()
        presence.shown = true
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.12
            panel.animator().alphaValue = 1
        }
        // 앱 필터 목록은 표시 경로에서 빼고, 패널을 띄운 다음 런루프에서 읽는다
        DispatchQueue.main.async { [weak self] in
            guard let self, self.isOpen else { return }
            self.presence.apps = self.model.sourceApps()
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

    func finishHide() {
        var t = Transaction(); t.disablesAnimations = true
        withTransaction(t) { presence.shown = false }
        panel?.orderOut(nil)
        previewLoader.clear()
    }

    // MARK: 생성

    func makePanel() -> ClipPanel {
        let panel = ClipPanel(contentRect: NSRect(x: 0, y: 0, width: Layout.panelWidth, height: Layout.panelHeight),
                              styleMask: [.nonactivatingPanel, .borderless],
                              backing: .buffered, defer: false)
        // 제목 막대가 없는 창: 상단 띠도 내용 뷰의 WindowDragArea가 받는다. 모양(둥근 모서리·그림자)은 직접 만든다.
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.isReleasedWhenClosed = false
        panel.hidesOnDeactivate = false
        panel.isMovableByWindowBackground = false
        panel.setAccessibilityLabel("Clipdeck 검색 패널")
        // 창 배경 전체가 아니라 PanelView의 WindowDragArea(빈 영역)에서만 끌어 옮긴다
        panel.onDragEnd = { [weak self] in self?.savePosition() }

        let effect = NSVisualEffectView()
        effect.material = .hudWindow
        effect.blendingMode = .behindWindow
        effect.state = .active
        effect.wantsLayer = true
        effect.layer?.cornerRadius = Layout.panelCorner
        effect.layer?.cornerCurve = .continuous
        effect.layer?.masksToBounds = true
        panel.contentView = effect

        let root = PanelView(model: model, presence: presence, loader: previewLoader,
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

    /// 마우스가 있는 화면에 저장된 위치(화면 안으로 보정). 없으면 그 화면의 중앙.
    func position(_ panel: NSPanel) {
        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { $0.frame.contains(mouse) } ?? NSScreen.main ?? NSScreen.screens[0]
        let origin = PanelPlacement.origin(saved: PanelOriginStore.load(for: screen),
                                           panelSize: CGSize(width: Layout.panelWidth, height: Layout.panelHeight),
                                           visibleFrame: screen.visibleFrame)
        panel.setFrameOrigin(origin)
    }

    /// 저장된 위치를 지운다(설정의 초기화 버튼)
    func resetSavedPosition() {
        PanelOriginStore.reset()
    }

    /// 드래그가 끝난 위치를 패널이 놓인 화면 기준으로 저장한다(끄는 동안에는 쓰지 않는다)
    func savePosition() {
        guard let panel, let screen = panel.screen else { return }
        PanelOriginStore.save(panel.frame.origin, for: screen)
    }

    func focusSearchField() {
        guard let panel, let field = Self.findSearchField(in: panel.contentView) else { return }
        panel.makeFirstResponder(field)
    }

    static func findSearchField(in view: NSView?) -> PanelSearchField? {
        guard let view else { return nil }
        if let f = view as? PanelSearchField { return f }
        for sub in view.subviews { if let f = findSearchField(in: sub) { return f } }
        return nil
    }

    static func plainTextHint(_ chord: KeyChord) -> String {
        ShortcutFormat.display(chord)
    }
}
