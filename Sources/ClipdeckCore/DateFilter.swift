import Foundation

/// 패널의 날짜 필터. nil(필터 없음)이 "전체 기간"이다.
public enum DateFilter: CaseIterable, Sendable, Equatable {
    case today, last7Days, last30Days

    /// 이 시각 이후에 사용한 항목만 보인다(`SearchQuery.since`)
    public func since(now: Date, calendar: Calendar = .current) -> Date {
        switch self {
        case .today: calendar.startOfDay(for: now)
        case .last7Days: now.addingTimeInterval(-7 * 86_400)
        case .last30Days: now.addingTimeInterval(-30 * 86_400)
        }
    }
}
