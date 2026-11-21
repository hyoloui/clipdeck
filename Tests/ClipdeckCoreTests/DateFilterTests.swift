import Foundation
import Testing
@testable import ClipdeckCore

@Suite struct DateFilterTests {
    private var utc: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        return c
    }

    @Test func sinceDates() {
        let now = Date(timeIntervalSince1970: 1_763_700_000) // 2025-11-21 04:40:00 UTC
        #expect(DateFilter.today.since(now: now, calendar: utc) == Date(timeIntervalSince1970: 1_763_683_200)) // 그날 00:00
        #expect(DateFilter.last7Days.since(now: now, calendar: utc) == now.addingTimeInterval(-7 * 86_400))
        #expect(DateFilter.last30Days.since(now: now, calendar: utc) == now.addingTimeInterval(-30 * 86_400))
    }
}

@MainActor
@Suite struct PanelDateFilterTests {
    @Test func sinceFilterLimitsItemsAndResetsOnShow() throws {
        let (store, dir) = try makeTempStore()
        defer { try? FileManager.default.removeItem(at: dir) }
        let now = Date()
        _ = try store.insert(textClip("old"), now: now.addingTimeInterval(-40 * 86_400))
        _ = try store.insert(textClip("mid"), now: now.addingTimeInterval(-10 * 86_400))
        _ = try store.insert(textClip("new"), now: now.addingTimeInterval(-3 * 86_400))
        let model = PanelModel(store: store)
        model.reload()
        #expect(model.items.count == 3)
        model.sinceFilter = .last7Days
        #expect(model.items.map(\.preview) == ["new"])
        model.sinceFilter = .last30Days
        #expect(model.items.map(\.preview) == ["new", "mid"])
        model.resetForShow()
        #expect(model.sinceFilter == nil)
        #expect(model.items.count == 3)
    }
}
