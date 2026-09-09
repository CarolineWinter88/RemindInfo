import XCTest
@testable import HabitStreakCore

final class HabitEngineTests: XCTestCase {
    let utc = TimeZone(identifier: "UTC")!
    let creation = { () -> Date in
        var c = DateComponents(); c.year = 2026; c.month = 1; c.day = 1; c.hour = 8
        var cal = Calendar(identifier: .gregorian); cal.timeZone = TimeZone(identifier: "UTC")!
        return cal.date(from: c)!
    }()

    private func makeEngine(target: Int = 2) -> (HabitEngine, [UUID]) {
        let settings = Settings(dailyTarget: target, dayCutoffHour: 3, intensity: .firm)
        var engine = HabitEngine(settings: settings, creationDate: creation, timeZone: utc)
        for i in 0..<5 {
            engine.addHabit(Habit(name: "h\(i)", slot: .morning, order: i))
        }
        return (engine, engine.habits.map(\.id))
    }

    /// creation 起第 offset 天的某个时刻。
    private func day(_ offset: Int, _ hour: Int = 10) -> Date {
        creation.addingTimeInterval(TimeInterval(offset * 86_400 + (hour - 8) * 3600))
    }

    // MARK: - Completion

    func testCompleteIsIdempotentPerHabitPerDay() {
        var (engine, ids) = makeEngine()
        XCTAssertTrue(engine.complete(habitId: ids[0], at: day(0)))
        XCTAssertFalse(engine.complete(habitId: ids[0], at: day(0, 15))) // 同一天重复
        XCTAssertEqual(engine.completedCount(forKey: engine.dateKey(for: day(0))), 1)
    }

    func testUncomplete() {
        var (engine, ids) = makeEngine()
        engine.complete(habitId: ids[0], at: day(0))
        let key = engine.dateKey(for: day(0))
        XCTAssertTrue(engine.uncomplete(habitId: ids[0], forKey: key))
        XCTAssertEqual(engine.completedCount(forKey: key), 0)
    }

    func testRemainingAndTodayMet() {
        var (engine, ids) = makeEngine(target: 2)
        XCTAssertEqual(engine.remainingToTarget(now: day(0)), 2)
        engine.complete(habitId: ids[0], at: day(0))
        XCTAssertFalse(engine.isTodayMet(now: day(0)))
        engine.complete(habitId: ids[1], at: day(0))
        XCTAssertTrue(engine.isTodayMet(now: day(0)))
        XCTAssertEqual(engine.remainingToTarget(now: day(0)), 0)
    }

    // MARK: - Settlement

    func testMetIncrementsStreak() {
        var (engine, ids) = makeEngine(target: 2)
        engine.complete(habitId: ids[0], at: day(0))
        engine.complete(habitId: ids[1], at: day(0))
        let settled = engine.settle(now: day(1)) // 结算 day0
        XCTAssertEqual(settled.count, 1)
        XCTAssertEqual(settled[0].status, .met)
        XCTAssertEqual(engine.streak.current, 1)
        XCTAssertEqual(engine.streak.lastMetDateKey, "2026-01-01")
    }

    func testMissedResetsCurrentPreservesLongest() {
        var (engine, ids) = makeEngine(target: 2)
        // 3 天达标
        for d in 0..<3 {
            engine.complete(habitId: ids[0], at: day(d))
            engine.complete(habitId: ids[1], at: day(d))
        }
        // day3 不做
        engine.settle(now: day(4))
        XCTAssertEqual(engine.streak.current, 0)
        XCTAssertEqual(engine.streak.longest, 3)
        XCTAssertEqual(engine.dayRecords["2026-01-04"]?.status, .missed)
    }

    /// 惰性日切：用户消失 N 天后回来，一次性正确补算。
    func testLazyCatchUpAfterDisappearance() {
        var (engine, ids) = makeEngine(target: 2)
        // day0, day1 达标
        for d in 0..<2 {
            engine.complete(habitId: ids[0], at: day(d))
            engine.complete(habitId: ids[1], at: day(d))
        }
        // 用户消失 5 天，第 7 天回来。settle 应补算 day0..day6。
        let settled = engine.settle(now: day(7))
        XCTAssertEqual(settled.count, 7)
        XCTAssertEqual(settled.map(\.status), [.met, .met, .missed, .missed, .missed, .missed, .missed])
        XCTAssertEqual(engine.streak.current, 0)
        XCTAssertEqual(engine.streak.longest, 2)
        XCTAssertEqual(engine.streak.lastSettledDateKey, "2026-01-07")
    }

    // MARK: - Freeze

    func testFreezeGrantedEveryTenMetDays() {
        var (engine, ids) = makeEngine(target: 1)
        for d in 0..<10 {
            engine.complete(habitId: ids[0], at: day(d))
        }
        engine.settle(now: day(10)) // 结算 day0..day9 = 10 个达标
        XCTAssertEqual(engine.streak.current, 10)
        XCTAssertEqual(engine.streak.freezesRemaining, 1)
        XCTAssertEqual(engine.streak.progressToNextFreeze, 0) // 满 10 归零
    }

    func testFreezeAutoConsumedPreservesStreak() {
        var (engine, ids) = makeEngine(target: 1)
        for d in 0..<10 { engine.complete(habitId: ids[0], at: day(d)) } // 10 天，得 1 张卡
        engine.complete(habitId: ids[0], at: day(11)) // day10 跳过（忘做），day11 做了
        engine.settle(now: day(12))
        XCTAssertEqual(engine.dayRecords["2026-01-11"]?.status, .frozen) // day10 = 2026-01-11
        XCTAssertEqual(engine.streak.freezesRemaining, 0)
        XCTAssertEqual(engine.streak.current, 11) // 连胜保住并继续（10 + day11）
        XCTAssertEqual(engine.consumeFreezeNotices(), ["2026-01-11"])
    }

    /// 连用限制：前一天是 frozen 则今天不可用，必须真实达标一天才解锁。
    func testFreezeConnectLimit() {
        var (engine, ids) = makeEngine(target: 1)
        for d in 0..<20 { engine.complete(habitId: ids[0], at: day(d)) } // 攒到 2 张卡
        XCTAssertEqual(engine.settle(now: day(20)).filter { $0.status == .met }.count, 20)
        XCTAssertEqual(engine.streak.freezesRemaining, 2)
        // day20, day21 都不做
        engine.settle(now: day(22))
        XCTAssertEqual(engine.dayRecords["2026-01-21"]?.status, .frozen) // day20
        XCTAssertEqual(engine.dayRecords["2026-01-22"]?.status, .missed) // day21，前一天 frozen → 不可连用
        XCTAssertEqual(engine.streak.current, 0)
        XCTAssertEqual(engine.streak.freezesRemaining, 1) // 只消耗了一张
    }

    func testFreezeCappedAtTwo() {
        var (engine, ids) = makeEngine(target: 1)
        for d in 0..<25 { engine.complete(habitId: ids[0], at: day(d)) } // 25 达标，理论 2 张
        engine.settle(now: day(25))
        XCTAssertEqual(engine.streak.freezesRemaining, maxFreezes)
    }

    // MARK: - Target snapshot

    /// DayRecord.target 必须快照，改达标线不能追溯性改写历史。
    func testTargetIsSnapshotAtSettlement() {
        var (engine, ids) = makeEngine(target: 3)
        engine.complete(habitId: ids[0], at: day(0)) // 只做 1 件，target=3 → 会 missed
        engine.settle(now: day(1))
        XCTAssertEqual(engine.dayRecords["2026-01-01"]?.status, .missed)
        XCTAssertEqual(engine.dayRecords["2026-01-01"]?.target, 3)

        // 事后把达标线降到 1，历史那天不应变成 met
        engine.settings.dailyTarget = 1
        XCTAssertEqual(engine.dayRecords["2026-01-01"]?.target, 3)
        XCTAssertEqual(engine.dayRecords["2026-01-01"]?.status, .missed)
    }

    func testSameDaySettleDoesNothing() {
        var (engine, ids) = makeEngine()
        engine.complete(habitId: ids[0], at: day(0))
        XCTAssertEqual(engine.settle(now: day(0)).count, 0) // 当天不结算
    }
}
