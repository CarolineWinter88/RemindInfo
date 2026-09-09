import Foundation

/// 把时刻映射到 `dateKey`，并提供 dateKey 之间的日期运算。
///
/// 关键点（产品文档「三、数据模型」）：`dateKey` 不按自然日切，默认凌晨 3 点。
/// 夜猫子 00:30 完成的任务在心理上属于「昨天」，按自然日算会造成莫名断签。
public struct DayKeyCalculator: Sendable {
    public let cutoffHour: Int
    public let timeZone: TimeZone
    private let calendar: Calendar

    public init(cutoffHour: Int, timeZone: TimeZone = TimeZone(identifier: "UTC")!) {
        self.cutoffHour = cutoffHour
        self.timeZone = timeZone
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = timeZone
        self.calendar = cal
    }

    private func makeFormatter() -> DateFormatter {
        let f = DateFormatter()
        f.calendar = calendar
        f.timeZone = timeZone
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        return f
    }

    /// 该时刻所属的 dateKey：先按 cutoffHour 回移，再取日历日期。
    public func dateKey(for date: Date) -> String {
        let shifted = date.addingTimeInterval(TimeInterval(-cutoffHour * 3600))
        return makeFormatter().string(from: shifted)
    }

    /// dateKey 当天的起始时刻（本地 cutoffHour 那一刻）。
    public func startInstant(ofKey key: String) -> Date? {
        guard let midnight = makeFormatter().date(from: key) else { return nil }
        return calendar.date(byAdding: .hour, value: cutoffHour, to: midnight)
    }

    /// 在 dateKey 上加减自然日。
    public func addingDays(_ days: Int, to key: String) -> String? {
        let f = makeFormatter()
        guard let date = f.date(from: key),
              let shifted = calendar.date(byAdding: .day, value: days, to: date)
        else { return nil }
        return f.string(from: shifted)
    }

    /// from（含）到 to（含）之间需要补算的日期序列，from 之后一直到 to。
    /// 若 from 为 nil，则只返回 [to]（首次结算）。
    public func daysToSettle(after lastSettled: String?, upToAndIncluding lastDay: String) -> [String] {
        guard let lastSettled else { return [lastDay] }
        var result: [String] = []
        var cursor = lastSettled
        while let next = addingDays(1, to: cursor) {
            if next > lastDay { break }
            result.append(next)
            cursor = next
        }
        return result
    }
}
