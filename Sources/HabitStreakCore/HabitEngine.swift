import Foundation

/// 「不能断」的核心领域引擎：数据模型 + 完成/取消 + 惰性日切结算 + 补签卡消耗。
///
/// 对应产品文档「附：建议的实现顺序」第 1、2 步——**无通知，纯逻辑跑通**，且可在任意平台
/// （含 Linux）运行与单测，不依赖 UIKit / UserNotifications。
public struct HabitEngine: Sendable {
    public private(set) var habits: [Habit]
    public private(set) var completions: [Completion]
    public private(set) var dayRecords: [String: DayRecord]
    public private(set) var streak: StreakState
    public var settings: Settings

    private let dayKey: DayKeyCalculator

    /// 待告知的补签卡消耗（次日进前台时告知，见产品文档「五」）。
    public private(set) var pendingFreezeNotices: [String]

    public init(
        settings: Settings = Settings(),
        creationDate: Date,
        timeZone: TimeZone = TimeZone(identifier: "UTC")!,
        habits: [Habit] = [],
        completions: [Completion] = [],
        streak: StreakState = StreakState()
    ) {
        self.settings = settings
        self.dayKey = DayKeyCalculator(cutoffHour: settings.dayCutoffHour, timeZone: timeZone)
        self.habits = habits
        self.completions = completions
        self.dayRecords = [:]
        self.pendingFreezeNotices = []

        var initial = streak
        if initial.lastSettledDateKey == nil {
            // 创建日之前没有历史。把 lastSettledDateKey 定在创建日的前一天，
            // 这样创建日当天不会被结算，之后从创建日开始补算。
            let creationKey = dayKey.dateKey(for: creationDate)
            initial.lastSettledDateKey = dayKey.addingDays(-1, to: creationKey)
        }
        self.streak = initial
    }

    // MARK: - Habits

    public mutating func addHabit(_ habit: Habit) {
        habits.append(habit)
    }

    public mutating func archiveHabit(id: UUID, at date: Date) {
        guard let idx = habits.firstIndex(where: { $0.id == id }) else { return }
        habits[idx].archivedAt = date
    }

    // MARK: - Completion

    public func dateKey(for date: Date) -> String {
        dayKey.dateKey(for: date)
    }

    /// 当天已完成的不同习惯数量。
    public func completedCount(forKey key: String) -> Int {
        var seen = Set<UUID>()
        for c in completions where c.dateKey == key {
            seen.insert(c.habitId)
        }
        return seen.count
    }

    public func isCompleted(habitId: UUID, forKey key: String) -> Bool {
        completions.contains { $0.habitId == habitId && $0.dateKey == key }
    }

    /// 标记完成。幂等：同一习惯同一天重复调用不会重复计数。
    @discardableResult
    public mutating func complete(
        habitId: UUID,
        at date: Date,
        source: CompletionSource = .app
    ) -> Bool {
        let key = dayKey.dateKey(for: date)
        guard !isCompleted(habitId: habitId, forKey: key) else { return false }
        completions.append(
            Completion(habitId: habitId, dateKey: key, completedAt: date, source: source)
        )
        return true
    }

    /// 取消完成（点错了）。
    @discardableResult
    public mutating func uncomplete(habitId: UUID, forKey key: String) -> Bool {
        let before = completions.count
        completions.removeAll { $0.habitId == habitId && $0.dateKey == key }
        return completions.count != before
    }

    /// 今天是否已达标（供重排引擎撤销当天剩余通知）。
    public func isTodayMet(now: Date) -> Bool {
        let key = dayKey.dateKey(for: now)
        return completedCount(forKey: key) >= settings.dailyTarget
    }

    /// 今天还差几件达标（用于「还剩 N 件」文案）。
    public func remainingToTarget(now: Date) -> Int {
        let key = dayKey.dateKey(for: now)
        return max(0, settings.dailyTarget - completedCount(forKey: key))
    }

    // MARK: - Lazy settlement

    /// 惰性日切结算：从 `lastSettledDateKey` 补算到「昨天」为止的所有未结算日期。
    ///
    /// 用户消失 N 天后回来，这 N 天的结算连同补签卡消耗要一次性正确算出。
    /// 见产品文档「五、日切结算」伪代码。
    @discardableResult
    public mutating func settle(now: Date) -> [DayRecord] {
        let todayKey = dayKey.dateKey(for: now)
        guard let yesterday = dayKey.addingDays(-1, to: todayKey) else { return [] }

        let days = dayKey.daysToSettle(
            after: streak.lastSettledDateKey,
            upToAndIncluding: yesterday
        )

        var settled: [DayRecord] = []
        for day in days {
            settled.append(settleOne(day: day))
        }
        return settled
    }

    private mutating func settleOne(day: String) -> DayRecord {
        let target = settings.dailyTarget // ★ 快照当天达标线
        let completed = completedCount(forKey: day)
        var rec = DayRecord(dateKey: day, target: target, completedCount: completed, status: .pending)

        let prevKey = dayKey.addingDays(-1, to: day)
        let prevStatus = prevKey.flatMap { dayRecords[$0]?.status }

        if completed >= target {
            rec.status = .met
            streak.current += 1
            streak.lastMetDateKey = day
            streak.progressToNextFreeze += 1
            if streak.progressToNextFreeze >= daysPerFreezeGrant && streak.freezesRemaining < maxFreezes {
                streak.freezesRemaining += 1
                streak.progressToNextFreeze = 0
            }
        } else if streak.freezesRemaining > 0 && prevStatus != .frozen {
            // 连用限制：前一天是 frozen 则今天不可用，必须真实达标一天才解锁。
            rec.status = .frozen
            streak.freezesRemaining -= 1
            pendingFreezeNotices.append(day)
            // streak.current 不变：不增不减
        } else {
            rec.status = .missed
            streak.longest = max(streak.longest, streak.current)
            streak.current = 0
        }

        dayRecords[day] = rec
        streak.lastSettledDateKey = day
        return rec
    }

    /// 消费掉待告知的补签卡提示（次日进前台后调用）。
    public mutating func consumeFreezeNotices() -> [String] {
        let notices = pendingFreezeNotices
        pendingFreezeNotices.removeAll()
        return notices
    }
}
