import Testing
import Foundation
@testable import ClipdeckCore

@Suite struct RetentionTests {
    @Test func purgeKeepsPinned() throws {
        let (store, dir) = try makeTempStore()
        defer { try? FileManager.default.removeItem(at: dir) }
        let now = Date(timeIntervalSince1970: 100 * 86_400)
        let old = now.addingTimeInterval(-40 * 86_400)
        guard case .inserted(let pinned) = try store.insert(textClip("pinned"), now: old),
              case .inserted(let loose) = try store.insert(textClip("loose"), now: old),
              case .inserted(let recent) = try store.insert(textClip("recent"), now: now) else {
            Issue.record("inserted 아님"); return
        }
        let board = try store.createPinboard(name: "keep", color: nil)
        try store.add(itemID: pinned, toPinboard: board)

        let removed = try store.purge(olderThan: now.addingTimeInterval(-30 * 86_400))
        #expect(removed == 1)
        #expect(try store.item(id: pinned) != nil)
        #expect(try store.item(id: loose) == nil)
        #expect(try store.item(id: recent) != nil)
    }

    @Test func cutoffValues() {
        let now = Date(timeIntervalSince1970: 1_000_000_000)
        #expect(RetentionPeriod.day.cutoff(from: now) == now.addingTimeInterval(-86_400))
        #expect(RetentionPeriod.week.cutoff(from: now) == now.addingTimeInterval(-7 * 86_400))
        #expect(RetentionPeriod.month.cutoff(from: now) == Calendar.current.date(byAdding: .month, value: -1, to: now))
        #expect(RetentionPeriod.year.cutoff(from: now) == Calendar.current.date(byAdding: .year, value: -1, to: now))
        #expect(RetentionPeriod.forever.cutoff(from: now) == nil)
    }
}

@Suite struct RetentionPlanTests {
    @Test func 기간_길이_비교() {
        #expect(RetentionPeriod.week.isShorter(than: .month))
        #expect(RetentionPeriod.month.isShorter(than: .forever))
        #expect(!RetentionPeriod.month.isShorter(than: .month))
        #expect(!RetentionPeriod.year.isShorter(than: .week))
    }

    @Test func 지워질_개수만_세고_지우지_않는다() throws {
        let (store, dir) = try makeTempStore()
        defer { try? FileManager.default.removeItem(at: dir) }
        let now = Date(timeIntervalSince1970: 100 * 86_400)
        let old = now.addingTimeInterval(-40 * 86_400)
        guard case .inserted(let pinned) = try store.insert(textClip("pinned"), now: old),
              case .inserted(let loose) = try store.insert(textClip("loose"), now: old) else {
            Issue.record("inserted 아님"); return
        }
        _ = try store.insert(textClip("recent"), now: now)
        try store.add(itemID: pinned, toPinboard: try store.createPinboard(name: "keep", color: nil))

        let cutoff = now.addingTimeInterval(-30 * 86_400)
        #expect(try store.purgeCount(olderThan: cutoff) == 1)
        #expect(try store.item(id: loose) != nil)
        #expect(try store.purge(olderThan: cutoff) == 1)
    }
}
