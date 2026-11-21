import AppKit
import SwiftUI

/// 설정 창. 일반 `NSWindow`이며 한 번 만들어 재사용한다.
@MainActor
final class SettingsWindowController: NSObject {
    private let model: SettingsModel
    private var window: NSWindow?

    init(model: SettingsModel) {
        self.model = model
    }

    func show() {
        model.reload()
        let window = self.window ?? makeWindow()
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
        window.center()
        self.window = window
        return window
    }
}
