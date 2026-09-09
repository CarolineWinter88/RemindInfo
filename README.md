# 不能断 (Badger)

> 一个会在你快要断签时越催越凶、你一完成就立刻闭嘴的每日习惯管理器。

完整产品定位、数据模型与机制见 [`product-spec-v1.md`](./product-spec-v1.md)。

## 仓库现状

最终产品是 iOS App，但仓库首先落地的是**平台无关的核心领域逻辑**——对应产品文档《附：建议的实现顺序》第 1、2 步：

> 数据模型 + 完成/取消 + 惰性日切结算 + 补签卡消耗（无通知，纯逻辑跑通）；
> 结算与重排的单元测试。

这部分不依赖 UIKit / UserNotifications，因此可以用 **Swift on Linux + SwiftPM** 构建、测试、运行，也就能在 Cloud Agent 环境里端到端验证。iOS UI 层（通知调度、Live Activity 等）后续在 macOS/Xcode 上叠加。

## 结构

```
Sources/HabitStreakCore/   核心领域逻辑（可跨平台）
  Models.swift             Habit / Completion / DayRecord / StreakState / Settings
  DayKey.swift             dateKey 凌晨 3 点日切 + 日期运算 + 补算区间
  HabitEngine.swift        完成/取消、惰性日切结算、补签卡自动生效与连用限制
Sources/StreakDemo/        端到端演示 (swift run streakdemo)
Tests/HabitStreakCoreTests 单元测试（重点覆盖多日补算与补签卡语义）
```

## 开发环境

Cloud Agent 通过 [`.cursor/environment.json`](./.cursor/environment.json) 自动执行 [`.cursor/install.sh`](./.cursor/install.sh)：安装 Swift 6.1.2 工具链及系统依赖，并运行 `swift build`。

本地（Ubuntu 24.04 x86_64）手动安装同理，然后：

```bash
swift build          # 构建
swift test           # 运行单元测试
swift run streakdemo # 运行端到端演示
```

## 已实现的核心不变式

- `dateKey` 按 `dayCutoffHour`（默认 3）切分，凌晨完成归属前一天，避免误伤断签。
- 惰性日切结算：用户消失 N 天后回来，一次性正确补算所有未结算日期。
- 补签卡自动生效：未达标且有库存时消耗一张、`status = frozen`，连胜不增不减。
- 连用限制：前一天是 frozen 则今天不可用，必须真实达标一天才解锁。
- 免费发放：每真实达标 10 天送 1 张，库存上限 2。
- `DayRecord.target` 结算时快照，事后改达标线不会追溯改写历史。
