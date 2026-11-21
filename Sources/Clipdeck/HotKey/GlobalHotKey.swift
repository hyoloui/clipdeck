import Carbon.HIToolbox
import ClipdeckCore
import os

/// Carbon `RegisterEventHotKey`로 만든 전역 단축키. 의존성 없이 앱이 활성 상태가 아니어도 동작한다.
@MainActor
final class GlobalHotKey {
    private static let log = Logger(subsystem: "local.hyoloui.clipdeck", category: "hotkey")
    private static let signature: OSType = 0x434B_4859 // 'CKHY'

    private let handler: () -> Void
    private var hotKeyRef: EventHotKeyRef?
    private var eventHandler: EventHandlerRef?
    /// 마지막 등록이 성공했는지. 다른 앱이 같은 조합을 쓰고 있으면 false다.
    private(set) var isRegistered = false

    init(spec: HotKeySpec, handler: @escaping () -> Void) {
        self.handler = handler
        installEventHandler()
        register(spec)
    }

    func update(_ spec: HotKeySpec) {
        unregister()
        register(spec)
    }

    /// 단축키가 눌린 것과 같은 효과를 낸다(등록이 막힌 환경에서의 확인용).
    func fire() { handler() }

    private func installEventHandler() {
        var type = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let status = InstallEventHandler(GetApplicationEventTarget(), { _, _, userData in
            guard let userData else { return OSStatus(eventNotHandledErr) }
            let hotKey = Unmanaged<GlobalHotKey>.fromOpaque(userData).takeUnretainedValue()
            // 애플리케이션 이벤트 타깃은 메인 스레드에서 호출된다
            MainActor.assumeIsolated { hotKey.handler() }
            return noErr
        }, 1, &type, Unmanaged.passUnretained(self).toOpaque(), &eventHandler)
        if status != noErr { Self.log.error("이벤트 핸들러 설치 실패: \(status)") }
    }

    private func register(_ spec: HotKeySpec) {
        let id = EventHotKeyID(signature: Self.signature, id: 1)
        let status = RegisterEventHotKey(spec.keyCode, spec.carbonModifiers, id, GetApplicationEventTarget(), 0, &hotKeyRef)
        isRegistered = status == noErr
        if !isRegistered {
            // eventHotKeyExistsErr(-9878): 다른 앱이 같은 조합을 이미 쓰는 경우
            Self.log.error("전역 단축키 등록 실패(상태 \(status)): keyCode \(spec.keyCode), modifiers \(spec.carbonModifiers)")
        }
    }

    private func unregister() {
        if let hotKeyRef { UnregisterEventHotKey(hotKeyRef) }
        hotKeyRef = nil
        isRegistered = false
    }
}
