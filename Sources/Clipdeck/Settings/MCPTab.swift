import AppKit
import ClipdeckCore
import SwiftUI
import os

/// DB 상태. 탭이 보일 때 읽는다.
@MainActor
private final class MCPStatus: ObservableObject {
    @Published var summary: ItemCountSummary?
    func refresh(_ store: ClipStore) { summary = try? store.itemCountSummary() }
}

struct MCPTab: View {
    private static let log = Logger(subsystem: "local.hyoloui.clipdeck", category: "settings")

    @ObservedObject var model: SettingsModel
    @StateObject private var status = MCPStatus()

    private var executablePath: String { MCPRegistration.executablePath(bundleURL: Bundle.main.bundleURL) }
    private var command: String { MCPRegistration.command(executablePath: executablePath) }

    var body: some View {
        Form {
            Section("등록") {
                copyRow("실행 파일", executablePath, copyLabel: "경로 복사")
                copyRow("등록 명령", command, copyLabel: "명령 복사")
            }
            Section("상태") {
                LabeledContent("실행 파일") {
                    Text(FileManager.default.isExecutableFile(atPath: executablePath) ? "있음" : "없음(앱 번들 안에서 확인)")
                }
                LabeledContent("데이터베이스") {
                    Text(ClipStore.defaultDirectory().appending(path: "clipdeck.sqlite").path)
                        .textSelection(.enabled).multilineTextAlignment(.trailing)
                }
                LabeledContent("항목 수") {
                    if let s = status.summary {
                        Text("전체 \(s.total)개 · MCP에 보임 \(s.mcpVisible)개")
                    } else {
                        Text("읽을 수 없음")
                    }
                }
            }
            Section {
                Toggle("비밀값 자동 숨김", isOn: model.binding(\.capture.detectSecrets))
                AppListEditor(ids: model.settings.capture.mcpHiddenBundleIDs,
                              emptyText: "숨길 앱이 없습니다.",
                              onAdd: addHiddenApp,
                              onRemove: { id in model.update { $0.capture.mcpHiddenBundleIDs.remove(id) } })
            } header: {
                Text("MCP에서 숨기기")
            } footer: {
                Text("앱을 추가하면 그 앱에서 이미 복사한 항목도 MCP에서 숨깁니다. 비밀값 자동 숨김은 키·토큰처럼 보이는 텍스트를 MCP에서 숨깁니다.")
            }
        }
        .formStyle(.grouped)
        .onAppear { status.refresh(model.store) }
    }

    private func copyRow(_ title: String, _ value: String, copyLabel: String) -> some View {
        LabeledContent(title) {
            VStack(alignment: .trailing, spacing: 4) {
                Text(value).font(.callout.monospaced()).textSelection(.enabled).multilineTextAlignment(.trailing)
                Button(copyLabel) { Self.copy(value) }
            }
        }
    }

    private func addHiddenApp(_ id: String) {
        model.update { $0.capture.mcpHiddenBundleIDs.insert(id) }
        do {
            try model.store.hideFromMCP(appBundleID: id)
            status.refresh(model.store)
        } catch {
            Self.log.error("기존 항목 MCP 숨김 실패: \(String(describing: error), privacy: .public)")
        }
    }

    /// 자체 표시를 붙여 써서 Clipdeck 기록에 남지 않게 한다
    private static func copy(_ text: String) {
        let pb = NSPasteboard.general
        pb.clearContents()
        let item = NSPasteboardItem()
        item.setString(text, forType: .string)
        item.setData(Data("1".utf8), forType: NSPasteboard.PasteboardType(PasteboardTypes.selfMarker))
        pb.writeObjects([item])
    }
}
