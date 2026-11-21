import Foundation
import Testing
@testable import ClipdeckCore

private func makeDefaults() -> UserDefaults {
    let name = "clipdeck-test-" + UUID().uuidString
    let d = UserDefaults(suiteName: name)!
    d.removePersistentDomain(forName: name)
    return d
}

@Suite struct AppSettingsTests {
    @Test func 기본값이_지시서와_같다() {
        let s = AppSettings()
        #expect(s.retention == .month)
        #expect(s.pasteToActiveApp)
        #expect(!s.alwaysPlainText)
        #expect(s.soundEffects)
        #expect(s.showMenuBarIcon)
        #expect(s.hideDuringScreenSharing)
        #expect(s.openAtLogin)
        #expect(s.hotKey == HotKeySpec(keyCode: 9, carbonModifiers: 768))
        #expect(s.hotKey == .openPanel)
        #expect(s.panelKeys == PanelKeyBindings())
        #expect(s.panelKeys.plainText == KeyChord(keyCode: 36, modifiers: 131_072))
        #expect(s.panelKeys.nextBoard == KeyChord(keyCode: 48, modifiers: 0))
        #expect(s.panelKeys.previousBoard == KeyChord(keyCode: 48, modifiers: 131_072))
        #expect(s.capture == CapturePolicy(ignoredBundleIDs: AppSettings.defaultIgnoredApps))
        #expect(AppSettings.defaultIgnoredApps.contains("com.apple.keychainaccess"))
        #expect(AppSettings.defaultIgnoredApps.contains("com.apple.Passwords"))
    }

    @Test func 저장한_뒤_다시_읽으면_같다() {
        let store = SettingsStore(defaults: makeDefaults())
        var s = AppSettings()
        s.retention = .year
        s.alwaysPlainText = true
        s.capture.pausedUntil = Date(timeIntervalSince1970: 1_800_000_000)
        store.save(s)
        #expect(store.load() == s)
    }

    @Test func 저장된_값이_없으면_기본값() {
        #expect(SettingsStore(defaults: makeDefaults()).load() == AppSettings())
    }

    @Test func 알_수_없는_키가_있어도_읽힌다() throws {
        let d = makeDefaults()
        d.set(Data(#"{"retention":"week","futureKey":{"a":1}}"#.utf8), forKey: "settings")
        let s = SettingsStore(defaults: d).load()
        #expect(s.retention == .week)
        #expect(s.soundEffects)
    }

    @Test func 디코딩에_실패하면_기본값() {
        let d = makeDefaults()
        d.set(Data("not json".utf8), forKey: "settings")
        #expect(SettingsStore(defaults: d).load() == AppSettings())
        d.set(Data(#"{"retention":"decade"}"#.utf8), forKey: "settings")
        #expect(SettingsStore(defaults: d).load() == AppSettings())
    }
}
