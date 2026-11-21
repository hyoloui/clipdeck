import ClipdeckCore
import SwiftUI

/// 손쉬운 사용 권한 상태. 탭이 보이는 동안 1초 간격으로 갱신한다.
@MainActor
private final class AccessibilityStatus: ObservableObject {
    @Published var trusted = AccessibilityPermission.isTrusted
    private var timer: Timer?

    func start() {
        trusted = AccessibilityPermission.isTrusted
        timer?.invalidate()
        let t = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.trusted = AccessibilityPermission.isTrusted }
        }
        t.tolerance = 0.5
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }
}

struct PasteTab: View {
    @ObservedObject var model: SettingsModel
    @StateObject private var access = AccessibilityStatus()

    var body: some View {
        Form {
            Section {
                Toggle("현재 앱에 바로 붙여넣기", isOn: model.binding(\.pasteToActiveApp))
                Toggle("항상 일반 텍스트로 붙여넣기", isOn: model.binding(\.alwaysPlainText))
            } footer: {
                Text("끄면 항목을 클립보드에만 복사합니다.")
            }
            Section {
                LabeledContent("손쉬운 사용 권한") {
                    Text(access.trusted ? "허용됨" : "필요함")
                        .foregroundStyle(access.trusted ? Color.secondary : Color.orange)
                }
                Button("시스템 설정 열기") { AccessibilityPermission.openSettings() }
            } footer: {
                Text("바로 붙여넣기(⌘V 전송)에 필요합니다. 없으면 클립보드에만 복사됩니다.")
            }
        }
        .formStyle(.grouped)
        .onReceive(model.$isWindowVisible) { $0 ? access.start() : access.stop() }
    }
}
