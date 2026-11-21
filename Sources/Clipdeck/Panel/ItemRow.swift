import ClipdeckCore
import SwiftUI

extension ItemKind {
    var symbolName: String {
        switch self {
        case .text: "text.alignleft"
        case .link: "link"
        case .image: "photo"
        case .file: "doc"
        case .color: "paintpalette"
        }
    }

    var accessibleName: String {
        switch self {
        case .text: "텍스트"
        case .link: "링크"
        case .image: "이미지"
        case .file: "파일"
        case .color: "색상"
        }
    }
}

/// 상대 시각 표기("2분 전"). 포매터는 만드는 비용이 커서 하나만 쓴다.
@MainActor
enum RelativeTime {
    private static let formatter: RelativeDateTimeFormatter = {
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .short
        f.dateTimeStyle = .numeric
        return f
    }()

    static func string(from date: Date) -> String {
        if abs(date.timeIntervalSinceNow) < 5 { return "방금" }
        return formatter.localizedString(for: date, relativeTo: .now)
    }
}

/// 선택된 행의 위치를 패널 좌표로 알려 준다(⌘P 메뉴를 그 근처에 띄우기 위해).
struct SelectedRowFrameKey: PreferenceKey {
    static let defaultValue: CGRect = .zero
    static func reduce(value: inout CGRect, nextValue: () -> CGRect) { value = nextValue() }
}

struct ItemRow: View {
    let item: ClipItem
    /// 1–9면 단축키 순번, 아니면 nil
    let number: Int?
    let isSelected: Bool

    var body: some View {
        HStack(spacing: Layout.s8) {
            Text(number.map(String.init) ?? "")
                .font(.caption.monospacedDigit())
                .foregroundStyle(secondary)
                .frame(width: Layout.numberWidth)
            Image(systemName: item.mcpHidden ? "lock.fill" : item.kind.symbolName)
                .font(.callout)
                .foregroundStyle(secondary)
                .frame(width: Layout.iconWidth)
            Text(previewText)
                .font(.body)
                .lineLimit(1)
                .truncationMode(.tail)
                .foregroundStyle(primary)
                .frame(maxWidth: .infinity, alignment: .leading)
            Text(item.sourceAppName ?? "")
                .font(.caption)
                .lineLimit(1)
                .truncationMode(.tail)
                .foregroundStyle(secondary)
                .frame(width: Layout.appColumnWidth, alignment: .trailing)
            Text(RelativeTime.string(from: item.lastUsedAt))
                .font(.caption)
                .lineLimit(1)
                .truncationMode(.tail)
                .foregroundStyle(secondary)
                .frame(width: Layout.timeColumnWidth, alignment: .trailing)
        }
        .padding(.horizontal, Layout.s8)
        .frame(height: Layout.rowHeight)
        .background {
            // 선택 표시는 애니메이션 없이 즉시 바뀐다
            if isSelected {
                RoundedRectangle(cornerRadius: Layout.rowCorner, style: .continuous)
                    .fill(Color(nsColor: .selectedContentBackgroundColor))
                    .background(GeometryReader { geo in
                        Color.clear.preference(key: SelectedRowFrameKey.self, value: geo.frame(in: .named("panel")))
                    })
            }
        }
        .contentShape(Rectangle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private var primary: Color {
        isSelected ? Color(nsColor: .alternateSelectedControlTextColor) : .primary
    }

    private var secondary: Color {
        isSelected ? Color(nsColor: .alternateSelectedControlTextColor).opacity(0.8) : .secondary
    }

    /// 가려진 항목은 앞 4자와 "••••"만 보인다
    private var previewText: String {
        item.mcpHidden ? String(item.preview.prefix(4)) + "••••" : item.preview
    }

    private var accessibilityText: String {
        var parts: [String] = []
        if let number { parts.append("\(number)번") }
        parts.append(item.kind.accessibleName)
        parts.append(item.mcpHidden ? "가려진 항목" : item.preview)
        if let app = item.sourceAppName { parts.append(app) }
        parts.append(RelativeTime.string(from: item.lastUsedAt))
        return parts.joined(separator: ", ")
    }
}
