import AppKit
import SwiftUI

struct GeneralTab: View {
    @ObservedObject var model: SettingsModel

    var body: some View {
        Form {
            Section {
                Toggle("로그인 시 실행", isOn: model.binding(\.openAtLogin))
                if let error = model.loginItemError {
                    Text(error).font(.caption).foregroundStyle(.red)
                }
                Toggle("효과음", isOn: model.binding(\.soundEffects))
                Toggle("메뉴바 아이콘 표시", isOn: iconBinding)
            }
            Section {
                Button("패널 위치 초기화") { PanelOriginStore.reset() }
            } footer: {
                Text("패널을 끌어 옮긴 위치를 지우고, 다음에 열 때 화면 중앙에 띄웁니다.")
            }
        }
        .formStyle(.grouped)
    }

    /// 끄면 설정 창을 다시 열 길이가 패널의 ⌘, 뿐이므로 확인을 받는다
    private var iconBinding: Binding<Bool> {
        Binding(get: { model.settings.showMenuBarIcon }, set: { show in
            if !show {
                let alert = NSAlert()
                alert.messageText = "메뉴바 아이콘을 숨길까요?"
                alert.informativeText = "메뉴바 아이콘을 숨기면 패널에서 ⌘, 로 설정을 열 수 있습니다."
                alert.addButton(withTitle: "숨기기")
                alert.addButton(withTitle: "취소")
                guard alert.runModal() == .alertFirstButtonReturn else {
                    model.objectWillChange.send() // 토글 표시를 원래 값으로 되돌린다
                    return
                }
            }
            model.update { $0.showMenuBarIcon = show }
        })
    }
}
