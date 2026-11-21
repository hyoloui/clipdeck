import Combine
import Foundation
import os

/// 패널의 목록·선택·보드 상태. 화면(SwiftUI)은 이 값을 그대로 그린다.
@MainActor
public final class PanelModel: ObservableObject {
    private static let log = Logger(subsystem: "local.hyoloui.clipdeck", category: "panel-model")
    /// 화면에 보이는 최대 항목 수
    public static let displayLimit = 200

    /// 바꾸면 즉시(디바운스 없이) 다시 검색하고 선택을 맨 위로 돌린다.
    @Published public var query: String = "" {
        didSet {
            guard query != oldValue else { return }
            if query.isEmpty { queryClearedAt = Date() }
            selectedIndex = 0
            reload()
        }
    }
    @Published public var kindFilter: ItemKind? = nil {
        didSet {
            guard kindFilter != oldValue else { return }
            selectedIndex = 0
            reload()
        }
    }
    /// 출처 앱 번들 ID
    @Published public var appFilter: String? = nil {
        didSet {
            guard appFilter != oldValue else { return }
            selectedIndex = 0
            reload()
        }
    }
    /// 사용자가 검색어를 마지막으로 비운 시각(⌫ 보호용). 열 때의 초기화는 세지 않는다.
    public private(set) var queryClearedAt: Date?
    @Published public private(set) var items: [ClipItem] = []
    @Published public private(set) var selectedIndex: Int = 0
    /// 0은 "기록", 1부터는 `boards[i-1]`
    @Published public private(set) var boardIndex: Int = 0
    /// 마지막 읽기가 실패했으면 그 설명, 성공했으면 nil
    @Published public private(set) var loadError: String?
    public private(set) var boards: [Pinboard] = []

    public let store: ClipStore

    public init(store: ClipStore) {
        self.store = store
    }

    public var selectedItem: ClipItem? {
        items.indices.contains(selectedIndex) ? items[selectedIndex] : nil
    }

    /// 1–9 순번에 해당하는 항목. 범위 밖이면 nil.
    public func item(atShortcut n: Int) -> ClipItem? {
        guard (1...9).contains(n), items.indices.contains(n - 1) else { return nil }
        return items[n - 1]
    }

    /// 필터 메뉴에 쓸 출처 앱 목록(최근 사용 순)
    public func sourceApps() -> [(bundleID: String, name: String)] {
        (try? store.sourceApps()) ?? []
    }

    /// 보드 목록과 항목을 저장소에서 다시 읽는다. 선택은 범위 안으로만 보정한다.
    /// 실패하면 목록을 비우고 `loadError`를 채운다.
    public func reload() {
        do {
            boards = try store.pinboards()
            if boardIndex > boards.count { boardIndex = 0 }
            let boardID: Int64? = boardIndex == 0 ? nil : boards[boardIndex - 1].id
            let q = SearchQuery(text: query, kind: kindFilter, appBundleID: appFilter,
                                pinboardID: boardID, limit: Self.displayLimit)
            items = try store.search(q)
            loadError = nil
        } catch {
            Self.log.error("패널 목록 읽기 실패: \(String(describing: error), privacy: .public)")
            items = []
            loadError = String(describing: error)
        }
        selectedIndex = items.isEmpty ? 0 : min(selectedIndex, items.count - 1)
    }

    public func moveSelection(_ delta: Int) {
        guard !items.isEmpty else { return }
        selectedIndex = min(max(selectedIndex + delta, 0), items.count - 1)
    }

    public func select(index: Int) {
        guard items.indices.contains(index) else { return }
        selectedIndex = index
    }

    /// 탭을 직접 눌렀을 때. 범위 밖이면 무시한다.
    public func selectBoard(_ index: Int) {
        reload()
        guard (0...boards.count).contains(index) else { return }
        boardIndex = index
        selectedIndex = 0
        reload()
    }

    public func selectNextBoard() { switchBoard(by: 1) }
    public func selectPreviousBoard() { switchBoard(by: -1) }

    /// 패널을 열 때: 검색어·필터를 비우고 선택을 맨 위로, 보드를 "기록"으로 되돌린다.
    public func resetForShow() {
        boardIndex = 0
        selectedIndex = 0
        // 값이 바뀌면 각자 reload하므로, 마지막에 한 번 더 읽어 최신 상태를 보장한다
        kindFilter = nil
        appFilter = nil
        query = ""
        queryClearedAt = nil
        reload()
    }

    private func switchBoard(by step: Int) {
        reload()
        let count = boards.count + 1
        boardIndex = ((boardIndex + step) % count + count) % count
        selectedIndex = 0
        reload()
    }
}
