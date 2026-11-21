import AppKit
import ClipdeckCore
import os

/// 패널에서 고른 항목을 클립보드에 쓰고, 원래 앱에 ⌘V를 보낸다. 패널은 닫지 않는다(PanelController 몫).
@MainActor
final class PasteService {
    private static let log = Logger(subsystem: "local.hyoloui.clipdeck", category: "paste")

    private let store: ClipStore
    var settings: AppSettings
    private var previousApp: NSRunningApplication?
    /// 패널을 연 순간 Clipdeck 자신(설정 창 등)이 앞에 있었으면 true. 기억한 앱이 화면에 없는 예전 앱일 수 있어
    /// 바로 붙여넣지 않고 클립보드에만 복사한다.
    private(set) var suppressDirectPaste = false
    private var pasteTask: Task<Void, Never>?

    init(store: ClipStore, settings: AppSettings) {
        self.store = store
        self.settings = settings
    }

    /// 패널을 열기 직전에 부른다. Clipdeck 자신이면 이전 값을 유지한다.
    func rememberFrontmostApp() {
        pasteTask?.cancel()
        guard let app = NSWorkspace.shared.frontmostApplication else { return }
        suppressDirectPaste = app.processIdentifier == ProcessInfo.processInfo.processIdentifier
        if !suppressDirectPaste { previousApp = app }
    }

    func copyOnly(itemID: Int64) {
        guard writeToPasteboard(itemID: itemID, plainText: settings.alwaysPlainText) else { return }
        ToastWindow.shared.show("클립보드에 복사됨")
    }

    func paste(itemID: Int64, plainText: Bool) {
        pasteTask?.cancel()
        guard writeToPasteboard(itemID: itemID, plainText: plainText || settings.alwaysPlainText) else { return }
        guard settings.pasteToActiveApp, !suppressDirectPaste else {
            ToastWindow.shared.show("클립보드에 복사됨")
            return
        }
        guard AccessibilityPermission.isTrusted else {
            AccessibilityPermission.prompt()
            ToastWindow.shared.show("클립보드에 복사됨 · 바로 붙여넣기는 손쉬운 사용 권한 필요",
                                    opensAccessibilitySettings: true)
            return
        }
        guard let app = previousApp, !app.isTerminated else {
            ToastWindow.shared.show("클립보드에 복사됨")
            return
        }
        app.activate()
        pasteTask = Task { @MainActor in
            // 앞 앱 복귀와 수정 키(⇧↩의 ⇧ 등) 해제를 확인한 뒤 보낸다. 아니면 엉뚱한 앱·⇧⌘V가 된다
            var elapsed = 0
            while true {
                try? await Task.sleep(for: .milliseconds(elapsed == 0 ? PasteGate.minDelayMs : 25))
                if Task.isCancelled { return }
                elapsed += elapsed == 0 ? PasteGate.minDelayMs : 25
                let front = NSWorkspace.shared.frontmostApplication?.processIdentifier == app.processIdentifier
                let mods = PasteGate.modifiersDown(CGEventSource.flagsState(.combinedSessionState))
                switch PasteGate.decide(frontmostMatches: front, modifiersDown: mods, elapsedMs: elapsed) {
                case .send:
                    Self.sendCommandV()
                    if settings.soundEffects { NSSound(named: "Pop")?.play() }
                    return
                case .wait:
                    continue
                case .giveUp:
                    Self.log.error("앞 앱 복귀 또는 수정 키 해제 확인 실패: ⌘V 전송 생략")
                    ToastWindow.shared.show("클립보드에 복사됨")
                    return
                }
            }
        }
    }

    /// 클립보드에 쓰고 사용 기록을 갱신한다. 실패하면 HUD로 알리고 false.
    private func writeToPasteboard(itemID: Int64, plainText: Bool) -> Bool {
        do {
            let reps = PastePayload.build(try store.representations(itemID: itemID), plainTextOnly: plainText)
            let pb = NSPasteboard.general
            pb.clearContents()
            let items = PastePayload.groupForPasteboard(reps).map { group -> NSPasteboardItem in
                let item = NSPasteboardItem()
                for r in group { item.setData(r.data, forType: NSPasteboard.PasteboardType(r.uti)) }
                return item
            }
            pb.writeObjects(items)
            do { try store.markUsed(id: itemID) } catch {
                Self.log.error("사용 기록 갱신 실패(item \(itemID)): \(String(describing: error), privacy: .public)")
            }
            return true
        } catch {
            Self.log.error("붙여넣기 준비 실패(item \(itemID)): \(String(describing: error), privacy: .public)")
            ToastWindow.shared.show("붙여넣지 못했습니다")
            return false
        }
    }

    private static func sendCommandV() {
        let src = CGEventSource(stateID: .privateState)
        for down in [true, false] {
            let e = CGEvent(keyboardEventSource: src, virtualKey: 9, keyDown: down)
            e?.flags = .maskCommand
            e?.post(tap: .cghidEventTap)
        }
    }
}
