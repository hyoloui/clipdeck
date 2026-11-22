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

    /// 목록 행과 미리보기가 같은 주기로 시각 표기를 갱신해 서로 어긋나지 않게 한다
    /// 모든 화면이 같은 순간에 갱신되고 같은 기준 시각을 쓰도록 시작점을 고정한 일정
    static let schedule = PeriodicTimelineSchedule(from: Date(timeIntervalSinceReferenceDate: 0), by: 10)

    static func string(from date: Date, now: Date) -> String {
        if abs(date.timeIntervalSince(now)) < 10 { return "방금" }
        return formatter.localizedString(for: date, relativeTo: now)
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
            // 행은 항목이 바뀌지 않으면 다시 그려지지 않으므로, 시각 표기만 주기적으로 갱신한다
            TimelineView(RelativeTime.schedule) { context in
                Text(RelativeTime.string(from: item.lastUsedAt, now: context.date))
            }
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
        parts.append(RelativeTime.string(from: item.lastUsedAt, now: .now))
        return parts.joined(separator: ", ")
    }
}
