import AppKit
import ClipdeckCore
import SwiftUI

extension RetentionPeriod {
    var label: String {
        switch self {
        case .day: "1일"
        case .week: "1주"
        case .month: "1개월"
        case .year: "1년"
        case .forever: "무제한"
        }
    }
}

struct HistoryTab: View {
    @ObservedObject var model: SettingsModel

    var body: some View {
        Form {
            Section {
                Picker("보관 기간", selection: retentionBinding) {
                    ForEach(RetentionPeriod.allCases, id: \.self) { Text($0.label).tag($0) }
                }
            } footer: {
                Text("기간이 지난 항목은 앱을 켤 때와 하루에 한 번 지워집니다. Pinboard에 넣은 항목은 지워지지 않습니다.")
            }
            Section {
                Button("기록 전체 삭제…", role: .destructive) { HistoryEraser.confirmAndErase(store: model.store) }
            }
        }
        .formStyle(.grouped)
    }

    /// 줄일 때 지워질 개수를 확인받는다. 취소하면 바꾸지 않는다.
    private var retentionBinding: Binding<RetentionPeriod> {
        Binding(get: { model.settings.retention }, set: { new in
            if new.isShorter(than: model.settings.retention), let cutoff = new.cutoff(from: .now) {
                let count: Int
                do {
                    count = try model.store.purgeCount(olderThan: cutoff)
                } catch {
                    let failure = NSAlert()
                    failure.messageText = "지워질 항목 수를 확인하지 못했습니다"
                    failure.informativeText = "보관 기간을 바꾸지 않았습니다.\n\(error.localizedDescription)"
                    failure.runModal()
                    model.objectWillChange.send()
                    return
                }
                guard count > 0 else { model.update { $0.retention = new }; return }
                let alert = NSAlert()
                alert.messageText = "보관 기간을 \(new.label)로 줄일까요?"
                alert.informativeText = "\(count)개 항목이 지워집니다. Pinboard 항목은 지워지지 않습니다."
                alert.addButton(withTitle: "지우기")
                alert.addButton(withTitle: "취소")
                guard alert.runModal() == .alertFirstButtonReturn else {
                    model.objectWillChange.send() // 선택 표시를 원래 값으로 되돌린다
                    return
                }
            }
            model.update { $0.retention = new }
        })
    }
}
