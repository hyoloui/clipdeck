import AppKit
import ClipdeckCore
import SwiftUI

/// 패널 등장 상태와 화면 쪽에서만 쓰는 값. 컨트롤러가 값을 바꾸고 화면이 읽는다.
@MainActor
final class PanelPresence: ObservableObject {
    @Published var shown = false
    /// 가려진 항목 중 "보기"를 누른 항목
    @Published var revealedItemID: Int64?
    /// 패널을 열 때마다 1씩 늘어난다(스크롤 위치 초기화용)
    @Published var generation = 0
    /// 앱 필터 메뉴 목록. 열 때 한 번만 읽는다(타이핑마다 읽지 않는다).
    /// 푸터에 보이는 "일반 텍스트로 붙여넣기" 키 표기
    @Published var plainTextHint = "⇧↩"
    @Published var apps: [(bundleID: String, name: String)] = []
    /// 선택 행 위치(⌘P 메뉴 위치용). 화면을 다시 그릴 필요가 없어 @Published가 아니다.
    var selectedRowFrame: CGRect = .zero
}

/// 검색창. 컨트롤러가 첫 응답자로 직접 지정할 수 있도록 별도 클래스로 둔다.
final class PanelSearchField: NSTextField {}

struct SearchField: NSViewRepresentable {
    @Binding var text: String

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> PanelSearchField {
        let f = PanelSearchField()
        f.placeholderString = "검색…"
        f.isBordered = false
        f.drawsBackground = false
        f.focusRingType = .none
        f.font = .systemFont(ofSize: 17)
        f.lineBreakMode = .byTruncatingTail
        f.cell?.usesSingleLineMode = true
        f.delegate = context.coordinator
        f.setAccessibilityLabel("검색")
        return f
    }

    func updateNSView(_ f: PanelSearchField, context: Context) {
        context.coordinator.parent = self
        guard f.stringValue != text else { return }
        // 한글 조합 중에는 덮어쓰지 않는다
        if let editor = f.currentEditor() as? NSTextView, editor.hasMarkedText() { return }
        f.stringValue = text
    }

    final class Coordinator: NSObject, NSTextFieldDelegate {
        var parent: SearchField
        init(_ parent: SearchField) { self.parent = parent }

        func controlTextDidChange(_ obj: Notification) {
            guard let f = obj.object as? NSTextField else { return }
            parent.text = f.stringValue
        }
    }
}

/// 미리보기를 다시 읽을 계기: 보여줄 항목이 바뀌거나 패널을 새로 열었을 때(닫을 때 미리보기를 비우므로)
private struct PreviewTarget: Equatable {
    let itemID: Int64?
    let generation: Int
}

struct PanelView: View {
    @ObservedObject var model: PanelModel
    @ObservedObject var presence: PanelPresence
    @ObservedObject var loader: PreviewLoader
    let onActivate: (ClipItem) -> Void
    let onNewBoard: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            HStack(spacing: 0) {
                list.frame(width: Layout.listWidth)
                Divider()
                PreviewView(item: model.selectedItem, loaded: loader.loaded, isRevealed: isRevealed,
                            onReveal: { presence.revealedItemID = model.selectedItem?.id })
            }
            Divider()
            footer
        }
        .frame(width: Layout.panelWidth, height: Layout.panelHeight)
        // 제목 막대 safe area만큼 내용이 밀리지 않게 한다
        .ignoresSafeArea()
        .coordinateSpace(name: "panel")
        .onPreferenceChange(SelectedRowFrameKey.self) { presence.selectedRowFrame = $0 }
        // 미리보기는 body에서 읽지 않고, 보여줄 항목이 바뀔 때 한 번 읽어 둔다
        .onChange(of: PreviewTarget(itemID: previewItem?.id, generation: presence.generation), initial: true) { _, _ in
            loader.show(previewItem)
        }
        // 등장: 스프링(끊고 되돌릴 수 있음). 동작 줄이기면 크기 변화 없이 페이드만.
        .scaleEffect(reduceMotion || presence.shown ? 1 : 0.97)
        .opacity(presence.shown ? 1 : 0)
        .animation(reduceMotion ? .easeOut(duration: 0.12) : .spring(response: 0.3, dampingFraction: 0.85),
                   value: presence.shown)
    }

    private var isRevealed: Bool {
        model.selectedItem.map { $0.id == presence.revealedItemID } ?? false
    }

    /// 내용을 읽어 보여줄 항목. 가려진 항목은 "보기" 전에는 읽지 않는다.
    private var previewItem: ClipItem? {
        guard let item = model.selectedItem, !item.mcpHidden || isRevealed else { return nil }
        return item
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: Layout.s8) {
            HStack(spacing: Layout.s8) {
                Image(systemName: "magnifyingglass")
                    .font(.title3)
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)
                SearchField(text: $model.query)
                    .frame(height: Layout.s24)
                kindMenu
                appMenu
                dateMenu
            }
            boardTabs
        }
        .padding(.horizontal, Layout.s16)
        // 투명 제목 막대(약 28pt)가 검색창 클릭을 가로채지 않도록 그 아래에서 시작한다
        .padding(.top, Layout.s16 + Layout.s16)
        .padding(.bottom, Layout.s8)
    }

    private var boardTabs: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: Layout.s4) {
                tab("기록", index: 0)
                ForEach(Array(model.boards.enumerated()), id: \.element.id) { i, board in
                    tab(board.name, index: i + 1)
                }
                Button(action: onNewBoard) {
                    Image(systemName: "plus")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .frame(width: Layout.s24, height: Layout.s24)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("새 보드 만들기")
            }
        }
        .frame(height: Layout.s24)
    }

    private func tab(_ title: String, index: Int) -> some View {
        let selected = model.boardIndex == index
        return Text(title)
            .font(.callout.weight(selected ? .semibold : .regular))
            .foregroundStyle(selected ? Color.primary : Color.secondary)
            .lineLimit(1)
            .padding(.horizontal, Layout.s8)
            .frame(height: Layout.s24)
            .background(selected ? Color.primary.opacity(0.1) : Color.clear, in: Capsule())
            .contentShape(Capsule())
            .onTapGesture { model.selectBoard(index) }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(title)
            .accessibilityAddTraits(selected ? [.isButton, .isSelected] : .isButton)
    }

    @ViewBuilder
    private var list: some View {
        if let error = model.loadError {
            VStack(spacing: Layout.s8) {
                Text("기록을 불러오지 못했습니다").font(.callout)
                Text(error).font(.caption).foregroundStyle(.tertiary).lineLimit(4)
            }
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.center)
            .padding(Layout.s16)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if model.items.isEmpty {
            Text(emptyMessage)
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(Array(model.items.enumerated()), id: \.element.id) { i, item in
                            ItemRow(item: item, number: i < 9 ? i + 1 : nil, isSelected: i == model.selectedIndex)
                                .id(item.id)
                                .onTapGesture { model.select(index: i) }
                                .simultaneousGesture(TapGesture(count: 2).onEnded { onActivate(item) })
                        }
                    }
                    .padding(Layout.s8)
                }
                // 선택 이동에 따른 스크롤은 애니메이션 없이 즉시
                .onChange(of: model.selectedIndex) { _, _ in
                    if let id = model.selectedItem?.id { proxy.scrollTo(id) }
                }
                .onChange(of: presence.generation) { _, _ in
                    if let id = model.items.first?.id { proxy.scrollTo(id, anchor: .top) }
                }
            }
        }
    }

    private var emptyMessage: String {
        if !model.query.isEmpty || model.kindFilter != nil || model.appFilter != nil || model.sinceFilter != nil {
            return "찾는 항목이 없습니다"
        }
        return model.boardIndex == 0 ? "복사한 내용이 여기에 쌓입니다" : "이 보드는 비어 있습니다"
    }

    private var footer: some View {
        Text("↩ 붙여넣기   \(presence.plainTextHint) 일반 텍스트   ⌘1-9 바로   ⌘P 고정   ⌘H MCP 숨김   ⌫ 삭제   esc 닫기")
            .font(.caption)
            .foregroundStyle(.secondary)
            .lineLimit(1)
            .minimumScaleFactor(0.8)
            .padding(.horizontal, Layout.s16)
            .frame(height: Layout.s24 + Layout.s4, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}
