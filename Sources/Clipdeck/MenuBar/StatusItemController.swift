import AppKit
import ClipdeckCore

/// 메뉴바 아이콘과 메뉴
@MainActor
final class StatusItemController: NSObject, NSMenuDelegate {

    var onOpen: (() -> Void)?
    var onOpenSettings: (() -> Void)?

    private let store: ClipStore
    private let settings: SettingsStore
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    private let menu = NSMenu()
    private var resumeTimer: Timer?

    init(store: ClipStore, settings: SettingsStore) {
        self.store = store
        self.settings = settings
        super.init()
        statusItem.isVisible = settings.load().showMenuBarIcon
        menu.delegate = self
        statusItem.menu = menu
        refresh()
    }

    // 메뉴를 열 때마다 현재 상태로 다시 그린다
    func menuNeedsUpdate(_ menu: NSMenu) { rebuildMenu() }

    private var pausedUntil: Date? {
        guard let d = settings.load().capture.pausedUntil, d > .now else { return nil }
        return d
    }

    /// 아이콘을 현재 일시정지 상태에 맞추고, 기한이 있으면 끝나는 때에 다시 갱신한다
    private func refresh() {
        let until = pausedUntil
        let symbol = until == nil ? "clipboard" : "pause.circle"
        let image = NSImage(systemSymbolName: symbol, accessibilityDescription: "Clipdeck")
        image?.isTemplate = true
        statusItem.button?.image = image

        resumeTimer?.invalidate()
        resumeTimer = nil
        if let until, until != .distantFuture {
            let t = Timer.scheduledTimer(withTimeInterval: until.timeIntervalSinceNow + 0.1, repeats: false) { [weak self] _ in
                MainActor.assumeIsolated { self?.refresh() }
            }
            t.tolerance = 1
            resumeTimer = t
        }
    }

    private func rebuildMenu() {
        menu.removeAllItems()
        menu.addItem(item("열기", #selector(open)))
        menu.addItem(.separator())

        if let until = pausedUntil {
            let label = until == .distantFuture
                ? "일시정지 중(무기한)"
                : "일시정지 중(\(until.formatted(date: .omitted, time: .shortened))까지)"
            let status = NSMenuItem(title: label, action: nil, keyEquivalent: "")
            status.isEnabled = false
            menu.addItem(status)
            menu.addItem(item("재개", #selector(resume)))
        } else {
            let pause = NSMenuItem(title: "일시정지", action: nil, keyEquivalent: "")
            let sub = NSMenu()
            for (title, seconds) in [("15분", 900.0), ("1시간", 3600), ("8시간", 28_800), ("무기한", -1)] {
                let it = item(title, #selector(pauseSelected(_:)))
                it.representedObject = seconds
                sub.addItem(it)
            }
            pause.submenu = sub
            menu.addItem(pause)
        }

        menu.addItem(.separator())
        menu.addItem(item("설정…", #selector(openSettings)))
        menu.addItem(item("기록 전체 삭제…", #selector(eraseHistory)))
        menu.addItem(.separator())
        menu.addItem(item("종료", #selector(quit)))
    }

    private func item(_ title: String, _ action: Selector) -> NSMenuItem {
        let it = NSMenuItem(title: title, action: action, keyEquivalent: "")
        it.target = self
        return it
    }

    @objc private func open() { onOpen?() }
    @objc private func openSettings() { onOpenSettings?() }
    @objc private func quit() { NSApp.terminate(nil) }

    @objc private func pauseSelected(_ sender: NSMenuItem) {
        guard let seconds = sender.representedObject as? Double else { return }
        setPausedUntil(seconds < 0 ? .distantFuture : Date.now.addingTimeInterval(seconds))
    }

    @objc private func resume() { setPausedUntil(nil) }

    private func setPausedUntil(_ date: Date?) {
        var s = settings.load()
        s.capture.pausedUntil = date
        settings.save(s)
        refresh()
    }

    @objc private func eraseHistory() { HistoryEraser.confirmAndErase(store: store) }

    /// 설정의 "메뉴바 아이콘 표시"에 맞춰 아이콘을 보이거나 숨긴다
    func setIconVisible(_ visible: Bool) { statusItem.isVisible = visible }
}
