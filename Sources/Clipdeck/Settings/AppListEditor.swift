import AppKit
import SwiftUI
import UniformTypeIdentifiers

enum AppPicker {
    /// `/Applications`에서 앱을 골라 번들 ID를 돌려준다. 취소하거나 번들 ID가 없으면 nil.
    @MainActor
    static func chooseBundleID() -> String? {
        let panel = NSOpenPanel()
        panel.title = "앱 선택"
        panel.directoryURL = URL(fileURLWithPath: "/Applications", isDirectory: true)
        panel.allowedContentTypes = [.application]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        guard panel.runModal() == .OK, let url = panel.url else { return nil }
        if let id = Bundle(url: url)?.bundleIdentifier { return id }
        let alert = NSAlert()
        alert.messageText = "번들 ID를 읽을 수 없는 앱입니다"
        alert.informativeText = url.lastPathComponent
        alert.runModal()
        return nil
    }

    /// 설치된 앱이면 이름, 아니면 번들 ID
    static func displayName(bundleID: String) -> String {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else { return bundleID }
        return FileManager.default.displayName(atPath: url.path).replacingOccurrences(of: ".app", with: "")
    }
}

/// 번들 ID 목록(이름 + 번들 ID)과 추가·삭제. 개인정보 탭과 MCP 탭이 함께 쓴다.
struct AppListEditor: View {
    let ids: Set<String>
    let emptyText: String
    let onAdd: (String) -> Void
    let onRemove: (String) -> Void

    var body: some View {
        if ids.isEmpty {
            Text(emptyText).foregroundStyle(.secondary)
        }
        ForEach(ids.sorted(), id: \.self) { id in
            LabeledContent {
                Button { onRemove(id) } label: { Image(systemName: "minus.circle") }
                    .buttonStyle(.borderless)
                    .accessibilityLabel("\(AppPicker.displayName(bundleID: id)) 삭제")
            } label: {
                VStack(alignment: .leading, spacing: 0) {
                    Text(AppPicker.displayName(bundleID: id))
                    Text(id).font(.caption).foregroundStyle(.secondary)
                }
            }
        }
        Button("앱 추가…") {
            if let id = AppPicker.chooseBundleID() { onAdd(id) }
        }
    }
}
