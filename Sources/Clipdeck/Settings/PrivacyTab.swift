import SwiftUI

struct PrivacyTab: View {
    @ObservedObject var model: SettingsModel

    var body: some View {
        Form {
            Section {
                Toggle("민감한 내용 제외", isOn: model.binding(\.capture.ignoreConcealed))
                Toggle("임시·자동 생성 내용 제외", isOn: model.binding(\.capture.ignoreTransient))
                Toggle("화면 공유 중 패널 숨김", isOn: model.binding(\.hideDuringScreenSharing))
            } footer: {
                Text("민감한 내용은 암호 관리자 등이 비밀로 표시한 복사본입니다.")
            }
            Section {
                AppListEditor(ids: model.settings.capture.ignoredBundleIDs,
                              emptyText: "제외한 앱이 없습니다.",
                              onAdd: { id in model.update { $0.capture.ignoredBundleIDs.insert(id) } },
                              onRemove: { id in model.update { $0.capture.ignoredBundleIDs.remove(id) } })
            } header: {
                Text("기록에서 제외할 앱")
            } footer: {
                Text("이 앱이 앞에 있을 때 복사한 내용은 저장하지 않습니다.")
            }
        }
        .formStyle(.grouped)
    }
}
