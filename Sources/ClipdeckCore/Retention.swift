import Foundation

public enum RetentionPeriod: String, Codable, CaseIterable, Sendable {
    case day, week, month, year, forever

    /// 이 기간이 `other`보다 짧은가(day < week < month < year < forever)
    public func isShorter(than other: RetentionPeriod) -> Bool {
        Self.allCases.firstIndex(of: self)! < Self.allCases.firstIndex(of: other)!
    }

    /// 이 시각보다 오래된 항목이 정리 대상이다. forever는 nil.
    public func cutoff(from now: Date) -> Date? {
        switch self {
        case .day: now.addingTimeInterval(-86_400)
        case .week: now.addingTimeInterval(-7 * 86_400)
        case .month: Calendar.current.date(byAdding: .month, value: -1, to: now)
        case .year: Calendar.current.date(byAdding: .year, value: -1, to: now)
        case .forever: nil
        }
    }
}

extension ClipStore {
    /// `last_used_at`이 cutoff보다 오래된 항목 중 Pinboard에 없는 것을 지우고 지운 개수를 돌려준다.
    @discardableResult
    public func purge(olderThan cutoff: Date) throws -> Int {
        let count = try purgeCount(olderThan: cutoff)
        // deleteItems가 자체 트랜잭션을 쓰므로 여기서 감싸지 않는다.
        try deleteItems(where: Self.purgeCondition, params: Self.purgeParams(cutoff))
        return count
    }

    /// `purge(olderThan:)`가 지울 항목 수. 지우지 않는다(설정의 확인 창용).
    public func purgeCount(olderThan cutoff: Date) throws -> Int {
        let row = try db.query("SELECT COUNT(*) AS n FROM items WHERE \(Self.purgeCondition)", Self.purgeParams(cutoff)).first
        if case .int(let n)? = row?["n"] { return Int(n) }
        return 0
    }

    private static let purgeCondition = """
        last_used_at < ? AND NOT EXISTS (SELECT 1 FROM pinboard_items WHERE item_id = items.id)
        """

    private static func purgeParams(_ cutoff: Date) -> [SQLValue] { [.double(cutoff.timeIntervalSince1970)] }
}
