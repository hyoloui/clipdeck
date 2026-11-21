import AppKit
import ClipdeckCore
import ServiceManagement
import os

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private static let log = Logger(subsystem: "local.hyoloui.clipdeck", category: "app")

    private let settings = SettingsStore()
    private var store: ClipStore?
    private var monitor: PasteboardMonitor?
    private var statusItem: StatusItemController?
    private var panelController: PanelController?
    private var pasteService: PasteService?
    private var hotKey: GlobalHotKey?
    private var purgeTimer: Timer?
    private var settingsWindow: SettingsWindowController?
    private var dbObserver: DBChangeObserver?

    func applicationDidFinishLaunching(_ notification: Notification) {
        MainMenu.install()
        let store: ClipStore
        do {
            store = try ClipStore(directory: ClipStore.defaultDirectory())
        } catch {
            Self.log.fault("저장소를 열 수 없음: \(String(describing: error), privacy: .public)")
            showStoreOpenFailure(error)
            NSApp.terminate(nil)
            return
        }
        self.store = store

        let panel = PanelController(store: store, settings: settings)
        panelController = panel
        let paste = PasteService(store: store, settings: settings.load())
        pasteService = paste
        panel.onWillShow = { paste.rememberFrontmostApp() }
        panel.onPaste = { id, plain in paste.paste(itemID: id, plainText: plain) }
        panel.onCopyOnly = { id in paste.copyOnly(itemID: id) }
        hotKey = GlobalHotKey(spec: settings.load().hotKey) { [weak panel] in panel?.toggle() }

        let model = SettingsModel(store: store, settingsStore: settings)
        model.apply = { [weak self] new, old in
            self?.applySettings(new, old: old) ?? SettingsApplyResult(settings: new)
        }
        // 단축키 녹화 중에는 전역 단축키 등록을 풀어 그 조합이 녹화기에 도달하게 한다
        model.recording.onRecordingChange = { [weak self] recording in
            if recording { self?.hotKey?.suspend() } else { self?.hotKey?.resume() }
        }
        let settingsWindow = SettingsWindowController(model: model)
        self.settingsWindow = settingsWindow
        panel.onOpenSettings = { [weak settingsWindow] in settingsWindow?.show() }

        statusItem = StatusItemController(store: store, settings: settings)
        statusItem?.onOpen = { [weak panel] in panel?.toggle() }
        statusItem?.onOpenSettings = { [weak settingsWindow] in settingsWindow?.show() }
        monitor = PasteboardMonitor(store: store, settings: settings, onCapture: {})
        monitor?.start()

        dbObserver = DBChangeObserver { [weak panel] in panel?.reloadIfOpen() }
        syncLoginItemOnFirstLaunch()

        // 보관 기간이 지난 항목 정리: 실행 시와 하루 1번
        purge()
        let t = Timer.scheduledTimer(withTimeInterval: 86_400, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.purge() }
        }
        t.tolerance = 3600
        purgeTimer = t
    }

    // MARK: 설정 반영

    /// 설정이 바뀌면 이 한 곳에서 각 부분에 반영한다. 캡처 정책(`PasteboardMonitor`)과 메뉴바 일시정지는
    /// 매번 `SettingsStore`에서 읽으므로 저장만으로 즉시 반영된다.
    /// 실패한 항목(단축키 등록, 로그인 항목)은 이전 값으로 되돌려 돌려준다.
    private func applySettings(_ new: AppSettings, old: AppSettings) -> SettingsApplyResult {
        var effective = new
        var result = SettingsApplyResult(settings: new)

        if new.hotKey != old.hotKey, hotKey?.update(new.hotKey) == false {
            effective.hotKey = old.hotKey
            result.hotKeyFailed = true
        }
        if new.openAtLogin != old.openAtLogin, let error = setLoginItem(new.openAtLogin) {
            effective.openAtLogin = old.openAtLogin
            result.loginItemError = error
        }

        pasteService?.settings = effective
        panelController?.applySettings(effective)
        statusItem?.setIconVisible(effective.showMenuBarIcon)
        if new.retention != old.retention { purge() }

        result.settings = effective
        return result
    }

    /// 실패하면 사용자에게 보일 오류 문구를 돌려준다
    private func setLoginItem(_ enabled: Bool) -> String? {
        let service = SMAppService.mainApp
        do {
            if enabled, service.status != .enabled { try service.register() }
            // 등록돼 있지 않거나 찾을 수 없는 상태에서 끄는 것은 오류가 아니다
            if !enabled, service.status != .notRegistered, service.status != .notFound { try service.unregister() }
            return nil
        } catch {
            Self.log.error("로그인 시 실행 설정 실패: \(String(describing: error), privacy: .public)")
            return "로그인 시 실행을 설정하지 못했습니다: \(error.localizedDescription)"
        }
    }

    /// 기본값이 "로그인 시 실행 켬"이므로 설치 후 첫 실행에서 한 번만 등록한다.
    /// 이후에는 사용자가 시스템 설정에서 끈 선택을 덮어쓰지 않는다.
    private func syncLoginItemOnFirstLaunch() {
        let key = "didSyncLoginItem"
        guard !UserDefaults.standard.bool(forKey: key), Bundle.main.bundleIdentifier == "local.hyoloui.clipdeck" else { return }
        guard settings.load().openAtLogin else { return }
        if let error = setLoginItem(true) {
            Self.log.error("\(error, privacy: .public)") // 실패하면 플래그를 남기지 않아 다음 실행에 다시 시도한다
        } else {
            UserDefaults.standard.set(true, forKey: key)
        }
    }

    // MARK: 보관 정리

    private func purge() {
        guard let cutoff = settings.load().retention.cutoff(from: .now) else { return }
        do {
            try store?.purge(olderThan: cutoff)
        } catch {
            Self.log.error("보관 기간 정리 실패: \(String(describing: error), privacy: .public)")
        }
    }

    // MARK: 오류

    private func showStoreOpenFailure(_ error: Error) {
        let alert = NSAlert()
        alert.alertStyle = .critical
        alert.messageText = "Clipdeck이 데이터를 열 수 없습니다"
        alert.informativeText = "\(error.localizedDescription)\n\n데이터 폴더: \(ClipStore.defaultDirectory().path)"
        alert.addButton(withTitle: "종료")
        NSApp.activate()
        alert.runModal()
    }
}
