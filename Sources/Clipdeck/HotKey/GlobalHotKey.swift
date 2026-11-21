import Carbon.HIToolbox
import ClipdeckCore
import os

/// Carbon `RegisterEventHotKey`로 만든 전역 단축키. 의존성 없이 앱이 활성 상태가 아니어도 동작한다.
@MainActor
final class GlobalHotKey {
    private static let log = Logger(subsystem: "local.hyoloui.clipdeck", category: "hotkey")
    private static let signature: OSType = 0x434B_4859 // 'CKHY'
    private static let hotKeyID: UInt32 = 1

    private let handler: () -> Void
    // deinit(비격리)에서 정리하므로 nonisolated(unsafe). 접근은 메인 스레드뿐이다.
    private nonisolated(unsafe) var hotKeyRef: EventHotKeyRef?
    private nonisolated(unsafe) var eventHandler: EventHandlerRef?
    private var spec: HotKeySpec
    /// 마지막 등록이 성공했는지. 다른 앱이 같은 조합을 쓰고 있으면 false다.
    private(set) var isRegistered = false

    init(spec: HotKeySpec, handler: @escaping () -> Void) {
        self.spec = spec
        self.handler = handler
        installEventHandler()
        isRegistered = register(spec)
    }

    deinit {
        if let hotKeyRef { UnregisterEventHotKey(hotKeyRef) }
        if let eventHandler { RemoveEventHandler(eventHandler) }
    }

    /// 새 조합으로 바꾼다. 새 등록이 실패하면 이전 조합을 되살리고 false를 돌려준다.
    @discardableResult
    func update(_ newSpec: HotKeySpec) -> Bool {
        unregister()
        if register(newSpec) {
            spec = newSpec
            isRegistered = true
            return true
        }
        isRegistered = register(spec)
        return false
    }

    private func installEventHandler() {
        var type = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let status = InstallEventHandler(GetApplicationEventTarget(), { _, event, userData in
            guard let event, let userData else { return OSStatus(eventNotHandledErr) }
            var id = EventHotKeyID()
            let got = GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID),
                                        nil, MemoryLayout<EventHotKeyID>.size, nil, &id)
            guard got == noErr, id.signature == GlobalHotKey.signature, id.id == GlobalHotKey.hotKeyID else {
                return OSStatus(eventNotHandledErr)
            }
            let hotKey = Unmanaged<GlobalHotKey>.fromOpaque(userData).takeUnretainedValue()
            // 애플리케이션 이벤트 타깃은 메인 스레드에서 호출된다
            MainActor.assumeIsolated { hotKey.handler() }
            return noErr
        }, 1, &type, Unmanaged.passUnretained(self).toOpaque(), &eventHandler)
        if status != noErr { Self.log.error("이벤트 핸들러 설치 실패: \(status)") }
    }

    private func register(_ spec: HotKeySpec) -> Bool {
        let id = EventHotKeyID(signature: Self.signature, id: Self.hotKeyID)
        let status = RegisterEventHotKey(spec.keyCode, spec.carbonModifiers, id, GetApplicationEventTarget(), 0, &hotKeyRef)
        if status != noErr {
            // eventHotKeyExistsErr(-9878): 다른 앱이 같은 조합을 이미 쓰는 경우
            Self.log.error("전역 단축키 등록 실패(상태 \(status)): keyCode \(spec.keyCode), modifiers \(spec.carbonModifiers)")
            hotKeyRef = nil
        }
        return status == noErr
    }

    private func unregister() {
        if let hotKeyRef { UnregisterEventHotKey(hotKeyRef) }
        hotKeyRef = nil
        isRegistered = false
    }
}
