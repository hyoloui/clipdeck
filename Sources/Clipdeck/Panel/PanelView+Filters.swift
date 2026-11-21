import ClipdeckCore
import SwiftUI

/// 검색창 옆 필터 메뉴(종류·앱·날짜)
extension PanelView {
    static let kinds: [(ItemKind?, String)] = [
        (nil, "전체"), (.text, "텍스트"), (.link, "링크"), (.image, "이미지"), (.file, "파일"), (.color, "색")
    ]

    var kindMenu: some View {
        let current = Self.kinds.first { $0.0 == model.kindFilter }?.1 ?? "전체"
        return Menu {
            ForEach(Self.kinds, id: \.1) { kind, title in
                Button(title) { model.kindFilter = kind }
            }
        } label: {
            Text(model.kindFilter == nil ? "종류" : current).lineLimit(1)
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .accessibilityLabel("종류 필터, 현재 \(current)")
    }

    var appMenu: some View {
        let apps = presence.apps
        let current = apps.first { $0.bundleID == model.appFilter }?.name ?? model.appFilter
        return Menu {
            Button("전체") { model.appFilter = nil }
            ForEach(apps, id: \.bundleID) { app in
                Button(app.name) { model.appFilter = app.bundleID }
            }
        } label: {
            Text(current ?? "앱").lineLimit(1).frame(maxWidth: 96)
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .accessibilityLabel("앱 필터, 현재 \(current ?? "전체")")
    }

    static let dates: [(DateFilter?, String)] = [
        (nil, "전체 기간"), (.today, "오늘"), (.last7Days, "최근 7일"), (.last30Days, "최근 30일")
    ]

    var dateMenu: some View {
        let current = Self.dates.first { $0.0 == model.sinceFilter }?.1 ?? "전체 기간"
        return Menu {
            ForEach(Self.dates, id: \.1) { filter, title in
                Button(title) { model.sinceFilter = filter }
            }
        } label: {
            Text(model.sinceFilter == nil ? "기간" : current).lineLimit(1)
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .accessibilityLabel("기간 필터, 현재 \(current)")
    }
}
