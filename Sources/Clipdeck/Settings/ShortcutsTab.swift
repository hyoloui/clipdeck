import ClipdeckCore
import SwiftUI

struct ShortcutsTab: View {
    @ObservedObject var model: SettingsModel

    var body: some View {
        Form {
            Section("전역") {
                LabeledContent("패널 열기") {
                    ShortcutRecorder(id: "hotkey", display: ShortcutFormat.display(model.settings.hotKey),
                                     session: model.recording, onRecord: recordHotKey)
                }
                if let error = model.hotKeyError {
                    Text(error).font(.caption).foregroundStyle(.red)
                }
            }
            Section {
                ForEach(PanelKeySlot.allCases, id: \.self) { slot in
                    LabeledContent(slot.label) {
                        ShortcutRecorder(id: slot.rawValue, display: ShortcutFormat.display(model.settings.panelKeys[slot]),
                                         session: model.recording) { code, mods in
                            record(slot, KeyChord(keyCode: code, modifiers: mods))
                        }
                    }
                }
            } header: {
                Text("패널 안에서만 동작")
            } footer: {
                Text("누른 뒤 새 키를 입력하세요. esc는 취소, ⌫는 변경 없음입니다.")
            }
        }
        .formStyle(.grouped)
    }

    private func recordHotKey(_ code: UInt16, _ mods: UInt) -> String? {
        let spec = HotKeySpec(keyCode: code, eventModifiers: mods)
        guard spec.hasRequiredModifier else { return "⌘, ⌃, ⌥ 중 하나를 포함해야 합니다" }
        if let reason = PanelKeyBindings.fixedKeyConflict(for: spec) { return reason }
        if let slot = model.settings.panelKeys.slot(using: spec) {
            return "\(ShortcutFormat.display(spec))은(는) 패널 안의 '\(slot.label)' 키와 같습니다."
        }
        model.update { $0.hotKey = spec }
        return nil
    }

    /// 겹치면 저장하지 않고 이유를 돌려준다
    private func record(_ slot: PanelKeySlot, _ chord: KeyChord) -> String? {
        if let reason = model.settings.panelKeys.conflict(for: slot, proposing: chord, globalHotKey: model.settings.hotKey) { return reason }
        model.update { $0.panelKeys[slot] = chord }
        return nil
    }
}
