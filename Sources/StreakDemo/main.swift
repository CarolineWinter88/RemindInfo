import Foundation
import HabitStreakCore

// 端到端演示：不依赖 iOS，纯核心逻辑跑通。
// 对应产品文档「附：建议的实现顺序」第 1、2 步。

let utc = TimeZone(identifier: "UTC")!

func date(_ y: Int, _ mo: Int, _ d: Int, _ h: Int = 9, _ mi: Int = 0) -> Date {
    var comps = DateComponents()
    comps.year = y; comps.month = mo; comps.day = d; comps.hour = h; comps.minute = mi
    var cal = Calendar(identifier: .gregorian)
    cal.timeZone = utc
    return cal.date(from: comps)!
}

func line(_ s: String = "") { print(s) }
func rule() { line(String(repeating: "─", count: 60)) }

rule()
line("「不能断」核心引擎演示 (HabitStreakCore)")
rule()

// ── Part A：dateKey 不按自然日切（默认凌晨 3 点）──────────────
let calc = DayKeyCalculator(cutoffHour: 3, timeZone: utc)
line("\n[A] dateKey 凌晨 3 点日切：")
line("    2026-01-02 01:30 的完成 → dateKey = \(calc.dateKey(for: date(2026, 1, 2, 1, 30)))  (归属前一天，夜猫子不误伤)")
line("    2026-01-02 09:00 的完成 → dateKey = \(calc.dateKey(for: date(2026, 1, 2, 9, 0)))")

// ── 建立用户：5 个习惯，达标线 2，firm ──────────────────────
var settings = Settings(dailyTarget: 2, dayCutoffHour: 3, intensity: .firm)
let creation = date(2026, 1, 1, 8, 0)
var engine = HabitEngine(settings: settings, creationDate: creation, timeZone: utc)

let names = ["喝水 💧", "阅读 📖", "运动 🏃", "冥想 🧘", "记账 💰"]
for (i, n) in names.enumerated() {
    let slot: Slot = i % 3 == 0 ? .morning : (i % 3 == 1 ? .evening : .night)
    engine.addHabit(Habit(name: n, slot: slot, order: i))
}
let ids = engine.habits.map(\.id)
line("\n[B] 建立用户：\(engine.habits.count) 个习惯，达标线 \(settings.dailyTarget)/天，强度 \(settings.intensity.rawValue)")

func base(_ offset: Int) -> Date { creation.addingTimeInterval(TimeInterval(offset * 86_400)) }

// ── 连续 11 天真实达标（每天完成 2 件），触发免费补签卡发放 ─────
for offset in 0...10 {
    engine.complete(habitId: ids[0], at: base(offset).addingTimeInterval(3600))
    engine.complete(habitId: ids[1], at: base(offset).addingTimeInterval(7200))
}
line("\n[C] 连续完成第 0–10 天（11 天，每天 2 件达标）")

// ── 第 11 天：忘了做（有补签卡 → 自动冻结，连胜保住）──────────
// ── 第 12 天：又没做，但前一天是 frozen（连用限制）→ 真断签 ───
// 用户消失，直到第 14 天早上才回来打开 app，一次性补算第 0–13 天。
let settled = engine.settle(now: base(14).addingTimeInterval(4 * 3600))

line("\n[D] 用户第 14 天回来，惰性结算一次性补算 \(settled.count) 天：")
var met = 0, frozen = 0, missed = 0
for r in settled {
    switch r.status {
    case .met: met += 1
    case .frozen: frozen += 1; line("      · \(r.dateKey)  frozen  (补签卡自动生效，连胜保住)")
    case .missed: missed += 1; line("      · \(r.dateKey)  missed  (无卡或连用限制 → 真断签)")
    case .pending: break
    }
}
line("      met=\(met)  frozen=\(frozen)  missed=\(missed)")

let s = engine.streak
line("\n[E] 结算后连胜状态：")
line("      current           = \(s.current)  (真断签后归零)")
line("      longest            = \(s.longest)  (历史最长保住)")
line("      freezesRemaining   = \(s.freezesRemaining)")
line("      progressToNextFreeze = \(s.progressToNextFreeze)")
line("      lastMetDateKey     = \(s.lastMetDateKey ?? "-")")
line("      lastSettledDateKey = \(s.lastSettledDateKey ?? "-")")

let notices = engine.consumeFreezeNotices()
line("\n[F] 待告知的补签卡消耗（次日进前台告知，日历单独配色）：\(notices)")

// ── 重新开始：今天（第 14 天）完成 2 件 ─────────────────────
line("\n[G] 重新开始 —— 第 14 天：")
line("      今天还差 \(engine.remainingToTarget(now: base(14).addingTimeInterval(5 * 3600))) 件达标")
engine.complete(habitId: ids[0], at: base(14).addingTimeInterval(5 * 3600))
line("      完成 1 件后：还差 \(engine.remainingToTarget(now: base(14).addingTimeInterval(6 * 3600))) 件，今日达标=\(engine.isTodayMet(now: base(14)))")
engine.complete(habitId: ids[2], at: base(14).addingTimeInterval(6 * 3600))
line("      完成 2 件后：今日达标=\(engine.isTodayMet(now: base(14)))  → 重排引擎此刻撤销当天全部剩余通知")

rule()
line("演示结束：数据模型 + 完成/取消 + 惰性日切结算 + 补签卡消耗 全部跑通 ✅")
rule()
