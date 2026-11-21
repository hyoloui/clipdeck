import AppKit
import SwiftUI

/// 설정 창. 일반 `NSWindow`이며 한 번 만들어 재사용한다.
@MainActor
final class SettingsWindowController: NSObject, NSWindowDelegate {
    private let model: SettingsModel
    private var window: NSWindow?
    /// 창을 열기 직전의 앞 앱. 닫을 때 되살려 다음 붙여넣기가 바로 직접 붙여넣기가 되게 한다.
    private var previousApp: NSRunningApplication?

    init(model: SettingsModel) {
        self.model = model
        super.init()
        model.recording.window = { [weak self] in self?.window }
    }

    func show() {
        if let front = NSWorkspace.shared.frontmostApplication,
           front.processIdentifier != ProcessInfo.processInfo.processIdentifier {
            previousApp = front
        }
        model.reload()
        let window = self.window ?? makeWindow()
        model.isWindowVisible = true
        NSApp.activate()
        window.makeKeyAndOrderFront(nil)
    }

    private func makeWindow() -> NSWindow {
        let controller = NSHostingController(rootView: SettingsView(model: model))
        controller.sizingOptions = [.preferredContentSize] // 탭을 바꾸면 내용 높이에 맞춰 창 높이가 바뀐다
        let window = NSWindow(contentViewController: controller)
        window.title = "Clipdeck 설정"
        window.styleMask = [.titled, .closable]
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.center()
        self.window = window
        return window
    }

    // MARK: NSWindowDelegate

    func windowWillClose(_ notification: Notification) {
        model.isWindowVisible = false
        if let app = previousApp, !app.isTerminated { app.activate() } else { NSApp.hide(nil) } // 되돌릴 앱이 없으면 Clipdeck을 앞에서 내린다
        previousApp = nil
    }

    func windowDidResignKey(_ notification: Notification) {
        model.recording.cancel()
    }
}
