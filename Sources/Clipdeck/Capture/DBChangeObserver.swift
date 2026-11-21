import Foundation

/// 다른 프로세스(MCP 서버)가 DB를 바꾸면 보내는 Darwin 알림 `local.hyoloui.clipdeck.db-changed`를 받는다.
/// 핸들러는 메인 스레드에서 불린다.
@MainActor
final class DBChangeObserver {
    static let notificationName = "local.hyoloui.clipdeck.db-changed"

    private let handler: @MainActor () -> Void

    init(handler: @escaping @MainActor () -> Void) {
        self.handler = handler
        CFNotificationCenterAddObserver(
            CFNotificationCenterGetDarwinNotifyCenter(), Unmanaged.passUnretained(self).toOpaque(),
            { _, observer, _, _, _ in
                guard let observer else { return }
                let me = Unmanaged<DBChangeObserver>.fromOpaque(observer).takeUnretainedValue()
                DispatchQueue.main.async { MainActor.assumeIsolated { me.handler() } }
            },
            Self.notificationName as CFString, nil, .deliverImmediately)
    }

    deinit {
        CFNotificationCenterRemoveEveryObserver(CFNotificationCenterGetDarwinNotifyCenter(),
                                                Unmanaged.passUnretained(self).toOpaque())
    }
}
