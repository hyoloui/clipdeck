import ClipdeckCore
import SwiftUI

/// 설정 반영 결과. `settings`는 실제로 적용된 값이다(실패한 항목은 이전 값으로 되돌려져 있다).
struct SettingsApplyResult {
    var settings: AppSettings
    var hotKeyFailed = false
    var loginItemError: String?
}

/// 설정 창이 읽고 쓰는 모델. 값의 원본은 `SettingsStore`이고, 바꿀 때마다 저장소에서 다시 읽어
/// (메뉴바의 일시정지처럼 다른 곳이 바꾼 값을 덮어쓰지 않도록) 한 곳(`apply`)으로 반영한다.
@MainActor
final class SettingsModel: ObservableObject {
    let store: ClipStore
    private let settingsStore: SettingsStore
    @Published private(set) var settings: AppSettings
    @Published var hotKeyError: String?
    @Published var loginItemError: String?
    /// (새 값, 이전 값) → 반영 결과. AppDelegate가 연결한다.
    var apply: ((AppSettings, AppSettings) -> SettingsApplyResult)?

    init(store: ClipStore, settingsStore: SettingsStore) {
        self.store = store
        self.settingsStore = settingsStore
        settings = settingsStore.load()
    }

    /// 창을 열 때 다른 곳에서 바뀐 값을 가져온다
    func reload() { settings = settingsStore.load() }

    func binding<V: Equatable>(_ keyPath: WritableKeyPath<AppSettings, V>) -> Binding<V> {
        Binding(get: { self.settings[keyPath: keyPath] },
                set: { value in self.update { $0[keyPath: keyPath] = value } })
    }

    func update(_ change: (inout AppSettings) -> Void) {
        let old = settingsStore.load()
        var new = old
        change(&new)
        guard new != old else { settings = old; return }
        settingsStore.save(new)
        let result = apply?(new, old) ?? SettingsApplyResult(settings: new)
        if result.settings != new { settingsStore.save(result.settings) }
        if result.settings.hotKey != old.hotKey || new.hotKey != old.hotKey {
            hotKeyError = result.hotKeyFailed ? "이 단축키는 등록할 수 없습니다(다른 앱이 쓰는 중일 수 있음)" : nil
        }
        if new.openAtLogin != old.openAtLogin { loginItemError = result.loginItemError }
        settings = result.settings
    }
}
