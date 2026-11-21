import ClipdeckCore
import SwiftUI

/// 설정 창 본문. 폭은 고정이고 높이는 탭 내용에 맞는다.
struct SettingsView: View {
    static let width: CGFloat = 560

    @ObservedObject var model: SettingsModel

    var body: some View {
        TabView(selection: $model.selectedTab) {
            GeneralTab(model: model)
                .tabItem { Label("일반", systemImage: "gearshape") }
                .tag(SettingsTab.general)
            ShortcutsTab(model: model)
                .tabItem { Label("단축키", systemImage: "keyboard") }
                .tag(SettingsTab.shortcuts)
            PasteTab(model: model)
                .tabItem { Label("붙여넣기", systemImage: "doc.on.clipboard") }
                .tag(SettingsTab.paste)
            HistoryTab(model: model)
                .tabItem { Label("기록", systemImage: "clock.arrow.circlepath") }
                .tag(SettingsTab.history)
            PrivacyTab(model: model)
                .tabItem { Label("개인정보", systemImage: "hand.raised") }
                .tag(SettingsTab.privacy)
            PinboardsTab(model: model)
                .tabItem { Label("Pinboard", systemImage: "pin") }
                .tag(SettingsTab.pinboards)
            MCPTab(model: model)
                .tabItem { Label("MCP", systemImage: "point.3.connected.trianglepath.dotted") }
                .tag(SettingsTab.mcp)
        }
        .frame(width: Self.width)
    }
}
