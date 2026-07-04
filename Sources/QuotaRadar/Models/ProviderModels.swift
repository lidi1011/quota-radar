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
    case tokenUsage
    case weeklyQuota
    case mcpUsage
    case multiplier

    var id: String { rawValue }

    var title: String {
        switch self {
        case .today: "今日"
        case .sevenDays: "近 7 天"
        case .total: "累计"
        case .planProgress: "羊毛进度"
        case .tokenUsage: "5 小时"
        case .weeklyQuota: "7 天限额"
        case .mcpUsage: "MCP"
        case .multiplier: "倍率"
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
