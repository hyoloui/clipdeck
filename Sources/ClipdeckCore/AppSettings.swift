import Foundation
import os

/// 전역 단축키 (Carbon 키 코드·수정자). 기본은 ⇧⌘V.
public struct HotKeySpec: Codable, Equatable, Sendable {
    public var keyCode: UInt32
    public var carbonModifiers: UInt32

    public init(keyCode: UInt32, carbonModifiers: UInt32) {
        self.keyCode = keyCode
        self.carbonModifiers = carbonModifiers
    }

    /// V(9) + cmdKey(256) + shiftKey(512)
    public static let openPanel = HotKeySpec(keyCode: 9, carbonModifiers: 768)
}

/// 패널 안에서만 동작하는 키. modifiers는 `NSEvent.ModifierFlags.rawValue`.
public struct KeyChord: Codable, Equatable, Sendable {
    public var keyCode: UInt16
    public var modifiers: UInt

    public init(keyCode: UInt16, modifiers: UInt) {
        self.keyCode = keyCode
        self.modifiers = modifiers
    }
}

// modifiers 131_072 = NSEvent.ModifierFlags.shift
public struct PanelKeyBindings: Codable, Equatable, Sendable {
    public var plainText: KeyChord
    public var nextBoard: KeyChord
    public var previousBoard: KeyChord

    public init(plainText: KeyChord = KeyChord(keyCode: 36, modifiers: 131_072),
                nextBoard: KeyChord = KeyChord(keyCode: 48, modifiers: 0),
                previousBoard: KeyChord = KeyChord(keyCode: 48, modifiers: 131_072)) {
        self.plainText = plainText
        self.nextBoard = nextBoard
        self.previousBoard = previousBoard
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = PanelKeyBindings()
        self.init(plainText: try c.decodeIfPresent(KeyChord.self, forKey: .plainText) ?? d.plainText,
                  nextBoard: try c.decodeIfPresent(KeyChord.self, forKey: .nextBoard) ?? d.nextBoard,
                  previousBoard: try c.decodeIfPresent(KeyChord.self, forKey: .previousBoard) ?? d.previousBoard)
    }
}

public struct AppSettings: Codable, Equatable, Sendable {
    public var retention: RetentionPeriod
    public var pasteToActiveApp: Bool
    public var alwaysPlainText: Bool
    public var soundEffects: Bool
    public var showMenuBarIcon: Bool
    public var hideDuringScreenSharing: Bool
    public var openAtLogin: Bool
    public var hotKey: HotKeySpec
    public var panelKeys: PanelKeyBindings
    public var capture: CapturePolicy

    /// 이 맥에서 확인한 키체인 접근·암호 앱의 번들 ID와, 널리 쓰는 비밀번호 관리자의 공개 번들 ID.
    /// 설치되지 않은 앱의 ID가 있어도 무해하다.
    public static let defaultIgnoredApps: Set<String> = [
        "com.apple.keychainaccess",
        "com.apple.Passwords",
        "com.1password.1password",
        "com.agilebits.onepassword7",
        "com.bitwarden.desktop",
    ]

    public init() {
        retention = .month
        pasteToActiveApp = true
        alwaysPlainText = false
        soundEffects = true
        showMenuBarIcon = true
        hideDuringScreenSharing = true
        openAtLogin = true
        hotKey = .openPanel
        panelKeys = PanelKeyBindings()
        capture = CapturePolicy(ignoredBundleIDs: Self.defaultIgnoredApps)
    }

    // 설정 파일에 없는 키는 기본값으로 채운다(버전 간 호환)
    public init(from decoder: Decoder) throws {
        self.init()
        let c = try decoder.container(keyedBy: CodingKeys.self)
        retention = try c.decodeIfPresent(RetentionPeriod.self, forKey: .retention) ?? retention
        pasteToActiveApp = try c.decodeIfPresent(Bool.self, forKey: .pasteToActiveApp) ?? pasteToActiveApp
        alwaysPlainText = try c.decodeIfPresent(Bool.self, forKey: .alwaysPlainText) ?? alwaysPlainText
        soundEffects = try c.decodeIfPresent(Bool.self, forKey: .soundEffects) ?? soundEffects
        showMenuBarIcon = try c.decodeIfPresent(Bool.self, forKey: .showMenuBarIcon) ?? showMenuBarIcon
        hideDuringScreenSharing = try c.decodeIfPresent(Bool.self, forKey: .hideDuringScreenSharing) ?? hideDuringScreenSharing
        openAtLogin = try c.decodeIfPresent(Bool.self, forKey: .openAtLogin) ?? openAtLogin
        hotKey = try c.decodeIfPresent(HotKeySpec.self, forKey: .hotKey) ?? hotKey
        panelKeys = try c.decodeIfPresent(PanelKeyBindings.self, forKey: .panelKeys) ?? panelKeys
        capture = try c.decodeIfPresent(CapturePolicy.self, forKey: .capture) ?? capture
    }
}

/// `UserDefaults` 키 `settings` 하나에 JSON으로 저장한다.
public final class SettingsStore: @unchecked Sendable {
    private let defaults: UserDefaults
    private static let key = "settings"
    private static let log = Logger(subsystem: "local.hyoloui.clipdeck", category: "settings")

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    /// 없거나 읽을 수 없으면 기본값
    public func load() -> AppSettings {
        guard let data = defaults.data(forKey: Self.key) else { return AppSettings() }
        do {
            return try JSONDecoder().decode(AppSettings.self, from: data)
        } catch {
            Self.log.error("설정을 읽지 못해 기본값을 씁니다: \(String(describing: error), privacy: .public)")
            return AppSettings()
        }
    }

    public func save(_ s: AppSettings) {
        guard let data = try? JSONEncoder().encode(s) else { return }
        defaults.set(data, forKey: Self.key)
    }
}
