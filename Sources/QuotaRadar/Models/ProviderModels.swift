import Foundation

enum ProviderID: String, CaseIterable, Codable, Identifiable, Sendable {
    case codex
    case glm

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .codex: "Codex"
        case .glm: "GLM"
        }
    }

    var subtitle: String {
        switch self {
        case .codex: "OpenAI Codex coding plan"
        case .glm: "ZAI / 智谱 coding plan"
        }
    }
}

enum UsageCardID: String, CaseIterable, Codable, Identifiable, Sendable {
    case today
    case sevenDays
    case total
    case planProgress
    case resetCredits
    case tokenUsage
    case weeklyQuota
    case mcpUsage
    case multiplier
    case subscriptionExpiry

    var id: String { rawValue }

    var title: String {
        switch self {
        case .today: "今日"
        case .sevenDays: "近 7 天"
        case .total: "累计"
        case .planProgress: "羊毛进度"
        case .resetCredits: "重置次数"
        case .tokenUsage: "5 小时"
        case .weeklyQuota: "7 天限额"
        case .mcpUsage: "MCP"
        case .multiplier: "倍率"
        case .subscriptionExpiry: "订阅到期"
        }
    }
}

struct UsageWindow: Identifiable, Codable, Equatable, Sendable {
    var id: String
    var label: String
    var remainingPercent: Double
    var usedPercent: Double
    var resetText: String

    static func placeholder(id: String, label: String) -> UsageWindow {
        UsageWindow(id: id, label: label, remainingPercent: 0, usedPercent: 0, resetText: "未连接")
    }
}

struct TokenBreakdown: Codable, Equatable, Sendable {
    var uncachedInput: Int
    var cachedInput: Int
    var output: Int
    var rawTotal: Int = 0

    var total: Int { max(rawTotal, uncachedInput + cachedInput + output) }

    static let zero = TokenBreakdown(uncachedInput: 0, cachedInput: 0, output: 0)
}

struct UsageCard: Identifiable, Codable, Equatable, Sendable {
    var id: UsageCardID
    var title: String
    var systemImage: String
    var primaryValue: String
    var trailingValue: String
    var breakdown: TokenBreakdown?
    var note: String?
    var progress: PlanProgress? = nil
}

struct PlanProgress: Codable, Equatable, Sendable {
    var title: String
    var currentValue: String
    var maxValue: String
    var progress: Double
    var markers: [PlanMarker]
}

struct PlanMarker: Identifiable, Codable, Equatable, Sendable {
    var id: String
    var label: String
    var position: Double
}

struct ProviderSnapshot: Identifiable, Codable, Equatable, Sendable {
    var id: ProviderID { provider }
    var provider: ProviderID
    var generatedAt: Date
    var windows: [UsageWindow]
    var cards: [UsageCard]
    var progress: PlanProgress?
    var statusMessage: String
}

enum SubscriptionInfoSource: String, Codable, Equatable, Sendable {
    case automatic
    case manual
    case unavailable

    var label: String {
        switch self {
        case .automatic: "自动读取"
        case .manual: "手动设置"
        case .unavailable: "未获取"
        }
    }
}

struct SubscriptionInfo: Codable, Equatable, Sendable {
    var expiresAt: Date?
    var renewsAt: Date?
    var planName: String?
    var source: SubscriptionInfoSource

    var targetDate: Date? {
        expiresAt ?? renewsAt
    }

    static func manual(_ date: Date?) -> SubscriptionInfo {
        guard let date else {
            return unavailable
        }
        return SubscriptionInfo(expiresAt: date, renewsAt: nil, planName: nil, source: .manual)
    }

    static let unavailable = SubscriptionInfo(expiresAt: nil, renewsAt: nil, planName: nil, source: .unavailable)

    func usageCard(now: Date = Date()) -> UsageCard {
        let note: String
        if let planName, !planName.isEmpty {
            note = "\(source.label) · \(planName)"
        } else if source == .unavailable {
            note = "未从接口读取到订阅到期时间"
        } else {
            note = source.label
        }

        return UsageCard(
            id: .subscriptionExpiry,
            title: UsageCardID.subscriptionExpiry.title,
            systemImage: "calendar.badge.exclamationmark",
            primaryValue: targetDate.map { RadarFormatters.subscriptionRemainingText($0, now: now) } ?? "未设置",
            trailingValue: targetDate.map(RadarFormatters.subscriptionDate) ?? "",
            breakdown: nil,
            note: note
        )
    }
}

enum ManualSubscriptionRule: Codable, Equatable, Sendable {
    case monthly(day: Int)
    case fixedDate(Date)

    var displayText: String {
        switch self {
        case .monthly(let day):
            "每月 \(Self.clampedDay(day)) 日"
        case .fixedDate(let date):
            RadarFormatters.subscriptionDate(date)
        }
    }

    func nextDate(now: Date = Date(), calendar: Calendar = RadarFormatters.localCalendar) -> Date {
        switch self {
        case .fixedDate(let date):
            return date
        case .monthly(let day):
            return Self.nextMonthlyDate(day: day, now: now, calendar: calendar)
        }
    }

    static func nextMonthlyDate(day: Int, now: Date = Date(), calendar: Calendar = RadarFormatters.localCalendar) -> Date {
        let start = calendar.startOfDay(for: now)
        let current = date(inSameMonthAs: start, day: day, calendar: calendar)
        if current >= start {
            return current
        }
        let nextMonth = calendar.date(byAdding: .month, value: 1, to: start) ?? start
        return date(inSameMonthAs: nextMonth, day: day, calendar: calendar)
    }

    private static func date(inSameMonthAs date: Date, day: Int, calendar: Calendar) -> Date {
        let components = calendar.dateComponents([.year, .month], from: date)
        let range = calendar.range(of: .day, in: .month, for: date)
        let maxDay = range?.count ?? 28
        var target = DateComponents()
        target.calendar = calendar
        target.timeZone = calendar.timeZone
        target.year = components.year
        target.month = components.month
        target.day = min(clampedDay(day), maxDay)
        return calendar.startOfDay(for: target.date ?? date)
    }

    private static func clampedDay(_ day: Int) -> Int {
        min(31, max(1, day))
    }
}

enum ProviderLoadState: Equatable, Sendable {
    case idle
    case loading
    case loaded(Date)
    case failed(String)

    var label: String {
        switch self {
        case .idle: "等待刷新"
        case .loading: "刷新中"
        case .loaded(let date): "已刷新 \(RadarFormatters.relative(date))"
        case .failed(let message): message
        }
    }
}
