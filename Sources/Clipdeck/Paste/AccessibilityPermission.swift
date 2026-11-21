import AppKit
import ApplicationServices

/// 손쉬운 사용 권한(⌘V 키 입력 전송에 필요)
enum AccessibilityPermission {
    private static let promptedKey = "didPromptAccessibility"
    private static let settingsURL = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!

    static var isTrusted: Bool { AXIsProcessTrusted() }

    /// 시스템 권한 요청 창을 띄운다. 앱 생애에 한 번만 부르고, 이후에는 아무것도 하지 않는다.
    static func prompt() {
        guard !UserDefaults.standard.bool(forKey: promptedKey) else { return }
        UserDefaults.standard.set(true, forKey: promptedKey)
        let key = "AXTrustedCheckOptionPrompt" // kAXTrustedCheckOptionPrompt (전역 var라 Swift 6에서 직접 참조 불가)
        _ = AXIsProcessTrustedWithOptions([key: true] as CFDictionary)
    }

    static func openSettings() {
        NSWorkspace.shared.open(settingsURL)
    }
}
