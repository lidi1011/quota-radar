import Foundation

struct GLMProvider: UsageProvider, Sendable {
    let id: ProviderID = .glm
    private static let mcpMeterLimit = 600
    private let authToken: String
    private let configuredBaseURL: String
    private let manualSubscriptionRule: ManualSubscriptionRule?
    private let cache: GLMQuotaCache
    private let client: GLMQuotaClient

    init(settings: AppSettings, cache: GLMQuotaCache, client: GLMQuotaClient = GLMQuotaClient()) {
        self.authToken = settings.glmAuthToken
        self.configuredBaseURL = settings.glmBaseURL
        self.manualSubscriptionRule = settings.glmManualSubscriptionRule
        self.cache = cache
        self.client = client
    }

    func snapshot(force: Bool) async throws -> ProviderSnapshot {
        let stats: GLMUsageStats
        if !force, let cached = await cache.current(ttlSeconds: 300) {
            stats = cached
        } else {
            stats = try await client.fetchUsageStats(
                token: resolvedToken(),
                baseURL: resolvedBaseURL()
            )
            await cache.update(stats)
        }

        let token = stats.tokenUsage
        let weekly = stats.weeklyUsage
        let mcp = stats.mcpUsage
        let multiplier = GLMMultiplierCalculator.currentInfo()
        let subscription = SubscriptionInfoResolver.resolve(
            automatic: stats.subscriptionInfo,
            manualRule: manualSubscriptionRule
        )

        let windows = [
            UsageWindow(
                id: "token",
                label: "5 小时",
                remainingPercent: max(0, 100 - Double(token?.percentage ?? 0)),
                usedPercent: Double(token?.percentage ?? 0),
                resetText: token?.resetDateTimeText ?? "--:--"
            ),
            UsageWindow(
                id: "weekly",
                label: "7 天",
                remainingPercent: max(0, 100 - Double(weekly?.percentage ?? 0)),
                usedPercent: Double(weekly?.percentage ?? 0),
                resetText: weekly?.resetDateTimeText ?? "新版套餐"
            )
        ]

        let cards = [
            UsageCard(id: .tokenUsage, title: "5 小时", systemImage: "gauge.with.dots.needle.bottom.50percent", primaryValue: token.map { "\($0.percentage)%" } ?? "N/A", trailingValue: token?.resetDateTimeText ?? "未返回重置", breakdown: nil, note: nil),
            UsageCard(id: .weeklyQuota, title: "7 天限额", systemImage: "calendar.badge.clock", primaryValue: weekly.map { "\($0.percentage)%" } ?? "N/A", trailingValue: "unit=6", breakdown: nil, note: nil),
            UsageCard(id: .mcpUsage, title: "MCP", systemImage: "point.3.connected.trianglepath.dotted", primaryValue: mcp.map { "\($0.percentage)%" } ?? "N/A", trailingValue: "TIME_LIMIT", breakdown: nil, note: mcp?.ratioText, meterValue: mcp.map(Self.mcpMeterValue)),
            UsageCard(id: .multiplier, title: "倍率", systemImage: "bolt.badge.clock", primaryValue: multiplier.displayValue, trailingValue: multiplier.periodLabel, breakdown: nil, note: multiplier.note(platform: stats.platformLabel)),
            subscription.usageCard()
        ]

        return ProviderSnapshot(
            provider: .glm,
            generatedAt: Date(),
            windows: windows,
            cards: cards,
            progress: nil,
            statusMessage: "直接读取 GLM/ZAI quota API"
        )
    }

    private func resolvedToken() throws -> String {
        let token = authToken.isEmpty ? ProcessInfo.processInfo.environment["ANTHROPIC_AUTH_TOKEN"] : authToken
        guard let token, !token.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw ProviderError.missingCredentials("缺少 GLM/ZAI token。请在设置中填写，或配置 ANTHROPIC_AUTH_TOKEN。")
        }
        return token
    }

    private func resolvedBaseURL() throws -> String {
        let baseURL = configuredBaseURL.isEmpty ? ProcessInfo.processInfo.environment["ANTHROPIC_BASE_URL"] : configuredBaseURL
        let resolved = baseURL?.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let resolved, !resolved.isEmpty else {
            return "https://open.bigmodel.cn/api/anthropic"
        }
        guard GLMPlatform.detect(from: resolved) != nil else {
            throw ProviderError.dataUnavailable("无法识别 GLM/ZAI 平台地址：\(resolved)")
        }
        return resolved
    }

    private static func mcpMeterValue(_ usage: GLMQuotaUsage) -> Double {
        let denominator = max(1, min(usage.limit, mcpMeterLimit))
        let remaining = 1 - Double(usage.used) / Double(denominator)
        return max(0, min(1, remaining))
    }
}

actor GLMQuotaCache {
    private var cached: (stats: GLMUsageStats, date: Date)?

    func current(ttlSeconds: TimeInterval) -> GLMUsageStats? {
        guard let cached, Date().timeIntervalSince(cached.date) < ttlSeconds else {
            return nil
        }
        return cached.stats
    }

    func update(_ stats: GLMUsageStats) {
        cached = (stats, Date())
    }
}

struct GLMQuotaClient: @unchecked Sendable {
    private let session: URLSession
    private let fetcher: (@Sendable (String, String) async throws -> GLMUsageStats)?

    init(session: URLSession = .shared) {
        self.session = session
        self.fetcher = nil
    }

    init(fetcher: @escaping @Sendable (String, String) async throws -> GLMUsageStats) {
        self.session = .shared
        self.fetcher = fetcher
    }

    func fetchUsageStats(token: String, baseURL: String) async throws -> GLMUsageStats {
        if let fetcher {
            return try await fetcher(token, baseURL)
        }

        let platform = GLMPlatform.detect(from: baseURL) ?? .zhipu
        let normalized = platform.normalizedBaseURL(baseURL)
        guard let url = URL(string: normalized + "/monitor/usage/quota/limit") else {
            throw ProviderError.dataUnavailable("GLM/ZAI quota URL 无效。")
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = 5
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        var lastError: Error?
        for _ in 0..<3 {
            do {
                let (data, response) = try await session.data(for: request)
                guard let http = response as? HTTPURLResponse else {
                    throw ProviderError.commandFailed("GLM/ZAI 没有返回 HTTP 响应。")
                }
                guard http.statusCode == 200 else {
                    throw ProviderError.commandFailed("GLM/ZAI quota API 返回 HTTP \(http.statusCode)。")
                }
                let subscriptionInfo = SubscriptionInfoParser.parse(data: data, source: .automatic)
                let decoded = try JSONDecoder().decode(GLMQuotaLimitResponse.self, from: data)
                guard decoded.success else {
                    throw ProviderError.commandFailed(decoded.msg)
                }
                return decoded.data.usageStats(platform: platform, subscriptionInfo: subscriptionInfo)
            } catch let error as ProviderError {
                throw error
            } catch {
                lastError = error
                try? await Task.sleep(nanoseconds: 100_000_000)
            }
        }
        throw lastError ?? ProviderError.commandFailed("GLM/ZAI quota API 请求失败。")
    }
}

enum GLMPlatform: String, Codable, Equatable, Sendable {
    case zai = "ZAI"
    case zhipu = "ZHIPU"

    static func detect(from baseURL: String) -> GLMPlatform? {
        if baseURL.contains("api.z.ai") {
            return .zai
        }
        if baseURL.contains("bigmodel.cn") || baseURL.contains("zhipu") {
            return .zhipu
        }
        return nil
    }

    func normalizedBaseURL(_ baseURL: String) -> String {
        var trimmed = baseURL.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        if self == .zhipu, trimmed.hasSuffix("/anthropic") {
            trimmed.removeLast("/anthropic".count)
        }
        return trimmed
    }
}

struct GLMUsageStats: Codable, Equatable, Sendable {
    var platform: GLMPlatform
    var tokenUsage: GLMQuotaUsage?
    var weeklyUsage: GLMQuotaUsage?
    var mcpUsage: GLMQuotaUsage?
    var subscriptionInfo: SubscriptionInfo? = nil

    var platformLabel: String { platform.rawValue }
}

struct GLMQuotaUsage: Codable, Equatable, Sendable {
    var used: Int
    var limit: Int
    var percentage: Int
    var timeWindow: String
    var resetAt: Date?

    var resetDateTimeText: String {
        guard let resetAt else { return "--:--" }
        return RadarFormatters.resetDateTime(resetAt)
    }

    var usageText: String {
        "\(RadarFormatters.compactTokens(used)) / \(RadarFormatters.compactTokens(limit))"
    }

    var ratioText: String {
        "\(used)/\(limit)"
    }
}

struct GLMMultiplierInfo: Equatable, Sendable {
    var value: Double
    var periodLabel: String
    var modelID: String
    var peakWindow: String

    var displayValue: String {
        GLMMultiplierCalculator.format(value)
    }

    func note(platform: String) -> String {
        "premium 模型 · \(modelID) · \(peakWindow) UTC+8 · \(platform)"
    }
}

enum GLMMultiplierCalculator {
    private static let premiumModels = ["glm-5", "glm-5.1", "glm-5.2", "glm-5-turbo"]
    private static let defaultModelID = "glm-5.2"
    private static let peakStart = "14:00"
    private static let peakEnd = "18:00"
    private static let peak = 3.0
    private static let offPeak = 2.0
    private static let promoOffPeak = 1.0
    private static let promoExpires = "2026-09-30"
    private static let utcPlus8: TimeZone = TimeZone(secondsFromGMT: 8 * 60 * 60) ?? .current

    static func currentInfo(date: Date = Date(), modelID: String = defaultModelID) -> GLMMultiplierInfo {
        let value = calculate(date: date, modelID: modelID)
        return GLMMultiplierInfo(
            value: value,
            periodLabel: periodLabel(date: date, value: value),
            modelID: modelID,
            peakWindow: "\(peakStart)-\(peakEnd)"
        )
    }

    static func calculate(date: Date, modelID: String?) -> Double {
        guard let modelID, isPremium(modelID) else { return 1.0 }
        guard let isPeak = isPeakTime(date) else { return 1.0 }
        if isPeak {
            return peak
        }
        return isPromoActive(date) ? promoOffPeak : offPeak
    }

    static func format(_ value: Double) -> String {
        if value.rounded(.down) == value {
            return "\(Int(value))x"
        }
        return "\(value)x"
    }

    private static func isPremium(_ modelID: String) -> Bool {
        let lowercased = modelID.lowercased()
        return premiumModels.contains { lowercased.contains($0.lowercased()) }
    }

    private static func isPeakTime(_ date: Date) -> Bool? {
        guard let start = minutes(from: peakStart), let end = minutes(from: peakEnd) else {
            return nil
        }
        let calendar = calendarUTC8
        let components = calendar.dateComponents([.hour, .minute], from: date)
        guard let hour = components.hour, let minute = components.minute else {
            return nil
        }
        let current = hour * 60 + minute
        return current >= start && current <= end
    }

    private static func isPromoActive(_ date: Date) -> Bool {
        guard let expiry = promoExpiryDate else { return false }
        let calendar = calendarUTC8
        return calendar.startOfDay(for: date) <= calendar.startOfDay(for: expiry)
    }

    private static func minutes(from value: String) -> Int? {
        let parts = value.split(separator: ":")
        guard parts.count == 2,
              let hour = Int(parts[0]),
              let minute = Int(parts[1]),
              (0...23).contains(hour),
              (0...59).contains(minute) else {
            return nil
        }
        return hour * 60 + minute
    }

    private static var promoExpiryDate: Date? {
        var components = DateComponents()
        components.calendar = calendarUTC8
        components.timeZone = utcPlus8
        components.year = 2026
        components.month = 9
        components.day = 30
        components.hour = 23
        components.minute = 59
        components.second = 59
        return components.date
    }

    private static var calendarUTC8: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = utcPlus8
        return calendar
    }

    private static func periodLabel(date: Date, value: Double) -> String {
        if isPeakTime(date) == true {
            return "高峰"
        }
        if value == promoOffPeak, isPromoActive(date) {
            return "促销"
        }
        return "非高峰"
    }
}

private struct GLMQuotaLimitResponse: Decodable {
    var code: Int?
    var msg: String
    var data: GLMQuotaLimitData
    var success: Bool
}

private struct GLMQuotaLimitData: Decodable {
    var limits: [GLMQuotaLimitItem]

    func usageStats(platform: GLMPlatform, subscriptionInfo: SubscriptionInfo?) -> GLMUsageStats {
        GLMUsageStats(
            platform: platform,
            tokenUsage: findQuota(type: "TOKENS_LIMIT", unit: 3, window: "5h"),
            weeklyUsage: findQuota(type: "TOKENS_LIMIT", unit: 6, window: "weekly"),
            mcpUsage: findQuota(type: "TIME_LIMIT", unit: nil, window: "30d"),
            subscriptionInfo: subscriptionInfo
        )
    }

    private func findQuota(type: String, unit: Int?, window: String) -> GLMQuotaUsage? {
        limits.first { item in
            guard item.type == type else { return false }
            if let unit {
                return item.unit == unit
            }
            return true
        }
        .map { item in
            GLMQuotaUsage(
                used: item.currentValue,
                limit: item.usage,
                percentage: min(100, max(0, item.percentage)),
                timeWindow: window,
                resetAt: item.nextResetTime.map { Date(timeIntervalSince1970: TimeInterval($0) / 1000) }
            )
        }
    }
}

private struct GLMQuotaLimitItem: Decodable {
    var type: String
    var unit: Int
    var usage: Int
    var currentValue: Int
    var percentage: Int
    var nextResetTime: Int?

    private enum CodingKeys: String, CodingKey {
        case type
        case unit
        case usage
        case currentValue
        case percentage
        case nextResetTime
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        type = try container.decode(String.self, forKey: .type)
        unit = try container.decodeIfPresent(Int.self, forKey: .unit) ?? 0
        usage = try container.decodeIfPresent(Int.self, forKey: .usage) ?? 0
        currentValue = try container.decodeIfPresent(Int.self, forKey: .currentValue) ?? 0
        percentage = try container.decodeIfPresent(Int.self, forKey: .percentage) ?? 0
        nextResetTime = try container.decodeIfPresent(Int.self, forKey: .nextResetTime)
    }
}

struct GLMUsageStatus: Equatable {
    var tokenPercent: Double
    var weeklyPercent: Double?
    var resetText: String?
    var mcpText: String?
    var multiplier: String?
}

enum GLMStatusParser {
    static func parse(_ output: String) -> GLMUsageStatus {
        let text = output.trimmingCharacters(in: .whitespacesAndNewlines)
        let percents = matches(text, pattern: #"(\d+(?:\.\d+)?)%"#).compactMap(Double.init)
        let tokenPercent = percents.first ?? 0
        let weeklyPercent = percents.dropFirst().first
        let reset = matches(text, pattern: #"(?:(?:⌛️|⏱)\s*)?(\d{1,2}:\d{2})"#).first
        let multiplier = matches(text, pattern: #"(\d+(?:\.\d+)?x)"#).first
        let mcp = matches(text, pattern: #"(\d+\s*/\s*\d+)"#).first?.replacingOccurrences(of: " ", with: "")
        return GLMUsageStatus(tokenPercent: tokenPercent, weeklyPercent: weeklyPercent, resetText: reset, mcpText: mcp, multiplier: multiplier)
    }

    private static func matches(_ text: String, pattern: String) -> [String] {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        return regex.matches(in: text, range: range).compactMap { match in
            guard match.numberOfRanges > 1, let range = Range(match.range(at: 1), in: text) else { return nil }
            return String(text[range])
        }
    }
}
