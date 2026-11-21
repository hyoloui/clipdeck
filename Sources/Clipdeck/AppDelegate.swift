import AppKit
import ClipdeckCore
import os

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private static let log = Logger(subsystem: "local.hyoloui.clipdeck", category: "app")

    private let settings = SettingsStore()
    private var store: ClipStore?
    private var monitor: PasteboardMonitor?
    private var statusItem: StatusItemController?
    private var purgeTimer: Timer?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let store: ClipStore
        do {
            store = try ClipStore(directory: ClipStore.defaultDirectory())
        } catch {
            Self.log.fault("저장소를 열 수 없음: \(String(describing: error), privacy: .public)")
            NSApp.terminate(nil)
            return
        }
        self.store = store

        statusItem = StatusItemController(store: store, settings: settings)
        monitor = PasteboardMonitor(store: store, settings: settings, onCapture: {})
        monitor?.start()

        // 보관 기간이 지난 항목 정리: 실행 시와 하루 1번
        purge()
        let t = Timer.scheduledTimer(withTimeInterval: 86_400, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.purge() }
        }
        t.tolerance = 3600
        purgeTimer = t
    }

    private func purge() {
        guard let cutoff = settings.load().retention.cutoff(from: .now) else { return }
        do {
            try store?.purge(olderThan: cutoff)
        } catch {
            Self.log.error("보관 기간 정리 실패: \(String(describing: error), privacy: .public)")
        }
    }
}
