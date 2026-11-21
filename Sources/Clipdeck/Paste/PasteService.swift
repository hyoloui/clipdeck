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

    init(store: ClipStore, settings: AppSettings) {
        self.store = store
        self.settings = settings
    }

    /// 패널을 열기 직전에 부른다. Clipdeck 자신이면 이전 값을 유지한다.
    func rememberFrontmostApp() {
        guard let app = NSWorkspace.shared.frontmostApplication,
              app.processIdentifier != ProcessInfo.processInfo.processIdentifier else { return }
        previousApp = app
    }

    func copyOnly(itemID: Int64) {
        guard writeToPasteboard(itemID: itemID, plainText: settings.alwaysPlainText) else { return }
        ToastWindow.shared.show("클립보드에 복사됨")
    }

    func paste(itemID: Int64, plainText: Bool) {
        guard writeToPasteboard(itemID: itemID, plainText: plainText || settings.alwaysPlainText) else { return }
        guard settings.pasteToActiveApp else {
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
        Task { @MainActor in
            // 활성화가 끝나기 전에 키가 가면 엉뚱한 앱에 붙으므로 frontmost 확인 후 보낸다
            try? await Task.sleep(for: .milliseconds(50))
            var waited = 0
            while NSWorkspace.shared.frontmostApplication?.processIdentifier != app.processIdentifier, waited < 300 {
                try? await Task.sleep(for: .milliseconds(25))
                waited += 25
            }
            guard NSWorkspace.shared.frontmostApplication?.processIdentifier == app.processIdentifier else {
                Self.log.error("앞 앱 복귀 확인 실패: ⌘V 전송 생략")
                ToastWindow.shared.show("클립보드에 복사됨")
                return
            }
            Self.sendCommandV()
            if settings.soundEffects { NSSound(named: "Pop")?.play() }
        }
    }

    /// 클립보드에 쓰고 사용 기록을 갱신한다. 실패하면 HUD로 알리고 false.
    private func writeToPasteboard(itemID: Int64, plainText: Bool) -> Bool {
        do {
            let reps = PastePayload.build(try store.representations(itemID: itemID), plainTextOnly: plainText)
            let pb = NSPasteboard.general
            pb.clearContents()
            let fileURLs = reps.filter { $0.uti == PasteboardTypes.fileURL }
            if fileURLs.count > 1 {
                // 파일 여러 개: 항목마다 NSPasteboardItem이 따로 있어야 한다
                let items = fileURLs.map { r -> NSPasteboardItem in
                    let item = NSPasteboardItem()
                    item.setData(r.data, forType: NSPasteboard.PasteboardType(r.uti))
                    return item
                }
                // 자체 쓰기 표시는 첫 항목에 붙인다(모니터는 types 전체에서 찾는다)
                items.first?.setData(Data(), forType: NSPasteboard.PasteboardType(PasteboardTypes.selfMarker))
                pb.writeObjects(items)
            } else {
                let item = NSPasteboardItem()
                for r in reps { item.setData(r.data, forType: NSPasteboard.PasteboardType(r.uti)) }
                pb.writeObjects([item])
            }
            try store.markUsed(id: itemID)
            return true
        } catch {
            Self.log.error("붙여넣기 준비 실패(item \(itemID)): \(String(describing: error), privacy: .public)")
            ToastWindow.shared.show("붙여넣지 못했습니다")
            return false
        }
    }

    private static func sendCommandV() {
        let src = CGEventSource(stateID: .combinedSessionState)
        for down in [true, false] {
            let e = CGEvent(keyboardEventSource: src, virtualKey: 9, keyDown: down)
            e?.flags = .maskCommand
            e?.post(tap: .cghidEventTap)
        }
    }
}
