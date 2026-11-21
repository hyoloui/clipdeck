import AppKit
import ClipdeckCore
import os

/// 0.5초마다 `NSPasteboard.general`의 changeCount를 확인해 새 클립을 저장한다.
/// 출처 앱 판정은 틱 시점의 앞 앱 하나가 아니라 직전 틱 이후 앞에 있던 앱들로 한다.
@MainActor
final class PasteboardMonitor {
    private static let log = Logger(subsystem: "local.hyoloui.clipdeck", category: "capture")
    /// 표현 하나가 이 크기를 넘으면 그 표현은 건너뛴다(메모리 보호)
    static let maxRepresentationBytes = 20 * 1024 * 1024

    private let store: ClipStore
    private let settings: SettingsStore
    private let onCapture: () -> Void
    private let pasteboard = NSPasteboard.general
    private var lastChangeCount: Int
    private var timer: Timer?
    private var activationObserver: NSObjectProtocol?
    /// 직전 확인 이후 앞에 있던 앱들(먼저 앞에 있던 순). 복사 직후 ⌘Tab으로 앱을 바꿔도 복사한 앱이 남아
    /// "제외 앱"·"MCP에서 숨길 앱" 판정이 빗나가지 않는다.
    private var recentApps: [(bundleID: String, name: String?)] = []

    init(store: ClipStore, settings: SettingsStore, onCapture: @escaping () -> Void) {
        self.store = store
        self.settings = settings
        self.onCapture = onCapture
        // 시작 시점의 내용은 기준값으로만 쓰고 저장하지 않는다
        lastChangeCount = pasteboard.changeCount
    }

    func start() {
        guard timer == nil else { return }
        resetRecentApps()
        activationObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main) { [weak self] note in
            let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
            let id = app?.bundleIdentifier, name = app?.localizedName
            MainActor.assumeIsolated { self?.noteActivated(bundleID: id, name: name) }
        }
        let t = Timer(timeInterval: 0.5, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
        t.tolerance = 0.1
        // 메뉴가 열려 있는 동안(추적 모드)에도 돌도록 common 모드로 등록
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        if let activationObserver { NSWorkspace.shared.notificationCenter.removeObserver(activationObserver) }
        activationObserver = nil
    }

    /// 다음 틱을 기다리지 않고 바로 확인한다(패널을 열기 직전 등)
    func checkNow() {
        tick()
    }

    private func noteActivated(bundleID: String?, name: String?) {
        guard let bundleID, !recentApps.contains(where: { $0.bundleID == bundleID }) else { return }
        recentApps.append((bundleID, name))
    }

    /// 기록을 지금 앞에 있는 앱 하나로 되돌린다(틱마다 새 구간을 시작한다)
    private func resetRecentApps() {
        recentApps = []
        let front = NSWorkspace.shared.frontmostApplication
        noteActivated(bundleID: front?.bundleIdentifier, name: front?.localizedName)
    }

    private func tick() {
        let count = pasteboard.changeCount
        // 이번 구간에 앞에 있던 앱들: 직전 틱 시점의 앞 앱 + 그 뒤 활성화된 앱들(+ 지금 앞 앱)
        let front = NSWorkspace.shared.frontmostApplication
        noteActivated(bundleID: front?.bundleIdentifier, name: front?.localizedName)
        let apps = recentApps
        resetRecentApps()
        guard count != lastChangeCount else { return }
        lastChangeCount = count

        let types = (pasteboard.types ?? []).map(\.rawValue)
        let policy = settings.load().capture
        let ids = apps.map(\.bundleID)
        guard policy.decide(types: types, recentBundleIDs: ids, now: .now) == .capture else {
            return
        }

        let reps = readRepresentations()
        guard let clip = ClipBuilder.make(representations: reps, recentBundleIDs: ids,
                                          sourceAppName: apps.first?.name, policy: policy) else { return }
        do {
            _ = try store.insert(clip)
            onCapture()
        } catch {
            Self.log.error("클립 저장 실패: \(String(describing: error), privacy: .public)")
        }
    }

    private func readRepresentations() -> [Representation] {
        var reps: [Representation] = []
        for type in pasteboard.types ?? [] {
            if type.rawValue == PasteboardTypes.fileURL {
                // 파일 여러 개 복사: 항목마다 file-url이 따로 있다
                for item in pasteboard.pasteboardItems ?? [] {
                    if let d = item.data(forType: type) { reps.append(Representation(uti: type.rawValue, data: d)) }
                }
                continue
            }
            guard let d = pasteboard.data(forType: type) else { continue }
            if d.count > Self.maxRepresentationBytes {
                Self.log.info("20MB 초과 표현 건너뜀: \(type.rawValue, privacy: .public)")
                continue
            }
            reps.append(Representation(uti: type.rawValue, data: d))
        }
        return reps
    }
}
