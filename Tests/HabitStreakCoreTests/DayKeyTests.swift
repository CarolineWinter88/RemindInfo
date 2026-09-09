import XCTest
@testable import HabitStreakCore

final class DayKeyTests: XCTestCase {
    let utc = TimeZone(identifier: "UTC")!

    private func date(_ y: Int, _ mo: Int, _ d: Int, _ h: Int, _ mi: Int = 0) -> Date {
        var c = DateComponents()
        c.year = y; c.month = mo; c.day = d; c.hour = h; c.minute = mi
        var cal = Calendar(identifier: .gregorian); cal.timeZone = utc
        return cal.date(from: c)!
    }

    func testCutoffAssignsPreDawnToPreviousDay() {
        let calc = DayKeyCalculator(cutoffHour: 3, timeZone: utc)
        // 00:30 属于前一天
        XCTAssertEqual(calc.dateKey(for: date(2026, 9, 9, 0, 30)), "2026-09-08")
        // 02:59 仍属于前一天
        XCTAssertEqual(calc.dateKey(for: date(2026, 9, 9, 2, 59)), "2026-09-08")
        // 03:00 起属于当天
        XCTAssertEqual(calc.dateKey(for: date(2026, 9, 9, 3, 0)), "2026-09-09")
        XCTAssertEqual(calc.dateKey(for: date(2026, 9, 9, 12, 0)), "2026-09-09")
    }

    func testAddingDaysAcrossMonthBoundary() {
        let calc = DayKeyCalculator(cutoffHour: 3, timeZone: utc)
        XCTAssertEqual(calc.addingDays(1, to: "2026-01-31"), "2026-02-01")
        XCTAssertEqual(calc.addingDays(-1, to: "2026-03-01"), "2026-02-28")
        XCTAssertEqual(calc.addingDays(1, to: "2028-02-28"), "2028-02-29") // 闰年
    }

    func testDaysToSettleCatchUp() {
        let calc = DayKeyCalculator(cutoffHour: 3, timeZone: utc)
        let days = calc.daysToSettle(after: "2026-01-01", upToAndIncluding: "2026-01-05")
        XCTAssertEqual(days, ["2026-01-02", "2026-01-03", "2026-01-04", "2026-01-05"])
    }

    func testDaysToSettleNothingWhenAlreadyCurrent() {
        let calc = DayKeyCalculator(cutoffHour: 3, timeZone: utc)
        XCTAssertEqual(calc.daysToSettle(after: "2026-01-05", upToAndIncluding: "2026-01-05"), [])
    }
}
