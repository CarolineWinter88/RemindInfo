import Foundation

/// 固定三档时段（v1）。见产品文档「三、数据模型」。
public enum Slot: String, Codable, CaseIterable, Sendable {
    case morning
    case evening
    case night
}

/// 完成记录来源。
public enum CompletionSource: String, Codable, Sendable {
    case app
    case notificationAction
    case backfill
}

/// 每日结算状态。
public enum DayStatus: String, Codable, Sendable {
    case pending
    case met
    case missed
    case frozen
}

/// 通知语气梯度。默认 firm。
public enum Intensity: String, Codable, CaseIterable, Sendable {
    case gentle
    case firm
    case relentless

    /// 升级链条数：gentle 1 / firm 2 / relentless 3。
    public var escalationCount: Int {
        switch self {
        case .gentle: return 1
        case .firm: return 2
        case .relentless: return 3
        }
    }
}

/// 习惯。
public struct Habit: Identifiable, Codable, Sendable, Equatable {
    public let id: UUID
    public var name: String
    public var emoji: String?
    public var slot: Slot
    /// 核心项不可被顶替；字段预留，v1 不暴露。
    public var isCore: Bool
    public var order: Int
    public var createdAt: Date
    /// 软删除，保留历史记录。
    public var archivedAt: Date?

    public init(
        id: UUID = UUID(),
        name: String,
        emoji: String? = nil,
        slot: Slot,
        isCore: Bool = false,
        order: Int = 0,
        createdAt: Date = Date(),
        archivedAt: Date? = nil
    ) {
        self.id = id
        self.name = name
        self.emoji = emoji
        self.slot = slot
        self.isCore = isCore
        self.order = order
        self.createdAt = createdAt
        self.archivedAt = archivedAt
    }

    public var isArchived: Bool { archivedAt != nil }
}

/// 完成记录。
public struct Completion: Identifiable, Codable, Sendable, Equatable {
    public let id: UUID
    public let habitId: UUID
    /// "2026-09-09"，按 dayCutoffHour 计算，非自然日。
    public let dateKey: String
    public let completedAt: Date
    public let source: CompletionSource

    public init(
        id: UUID = UUID(),
        habitId: UUID,
        dateKey: String,
        completedAt: Date,
        source: CompletionSource
    ) {
        self.id = id
        self.habitId = habitId
        self.dateKey = dateKey
        self.completedAt = completedAt
        self.source = source
    }
}

/// 每日结算，日切时生成。
public struct DayRecord: Codable, Sendable, Equatable {
    public let dateKey: String
    /// ★ 快照当天的达标线，历史必须冻结。
    public let target: Int
    public var completedCount: Int
    public var status: DayStatus

    public init(dateKey: String, target: Int, completedCount: Int, status: DayStatus) {
        self.dateKey = dateKey
        self.target = target
        self.completedCount = completedCount
        self.status = status
    }
}

/// 连胜状态。
public struct StreakState: Codable, Sendable, Equatable {
    public var current: Int
    public var longest: Int
    public var lastMetDateKey: String?
    /// 惰性结算用。
    public var lastSettledDateKey: String?
    /// 上限 2。
    public var freezesRemaining: Int
    /// 真实达标天数，满 10 送一张后归零。
    public var progressToNextFreeze: Int

    public init(
        current: Int = 0,
        longest: Int = 0,
        lastMetDateKey: String? = nil,
        lastSettledDateKey: String? = nil,
        freezesRemaining: Int = 0,
        progressToNextFreeze: Int = 0
    ) {
        self.current = current
        self.longest = longest
        self.lastMetDateKey = lastMetDateKey
        self.lastSettledDateKey = lastSettledDateKey
        self.freezesRemaining = freezesRemaining
        self.progressToNextFreeze = progressToNextFreeze
    }
}

/// 设置。
public struct Settings: Codable, Sendable, Equatable {
    /// 达标线。
    public var dailyTarget: Int
    /// 默认 3（凌晨 3 点前算前一天）。
    public var dayCutoffHour: Int
    public var intensity: Intensity
    /// 通知中不显示习惯名（锁屏隐私开关）。
    public var hideHabitNamesInNotifications: Bool

    public init(
        dailyTarget: Int = 2,
        dayCutoffHour: Int = 3,
        intensity: Intensity = .firm,
        hideHabitNamesInNotifications: Bool = false
    ) {
        self.dailyTarget = dailyTarget
        self.dayCutoffHour = dayCutoffHour
        self.intensity = intensity
        self.hideHabitNamesInNotifications = hideHabitNamesInNotifications
    }
}

/// 补签卡库存上限。
public let maxFreezes = 2
/// 每真实达标 N 天送 1 张。
public let daysPerFreezeGrant = 10
