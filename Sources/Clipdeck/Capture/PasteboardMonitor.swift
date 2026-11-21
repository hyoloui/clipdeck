import AppKit
import ClipdeckCore
import os

/// 0.5초마다 `NSPasteboard.general`의 changeCount를 확인해 새 클립을 저장한다.
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

    init(store: ClipStore, settings: SettingsStore, onCapture: @escaping () -> Void) {
        self.store = store
        self.settings = settings
        self.onCapture = onCapture
        // 시작 시점의 내용은 기준값으로만 쓰고 저장하지 않는다
        lastChangeCount = pasteboard.changeCount
    }

    func start() {
        guard timer == nil else { return }
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
    }

    private func tick() {
        let count = pasteboard.changeCount
        guard count != lastChangeCount else { return }
        lastChangeCount = count

        let types = (pasteboard.types ?? []).map(\.rawValue)
        let front = NSWorkspace.shared.frontmostApplication
        let policy = settings.load().capture
        guard policy.decide(types: types, frontmostBundleID: front?.bundleIdentifier, now: .now) == .capture else {
            return
        }

        let reps = readRepresentations()
        guard let clip = ClipBuilder.make(representations: reps, sourceAppBundleID: front?.bundleIdentifier,
                                          sourceAppName: front?.localizedName, policy: policy) else { return }
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
