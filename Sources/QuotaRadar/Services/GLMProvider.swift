import Foundation

struct GLMProvider: UsageProvider, Sendable {
    let id: ProviderID = .glm
    private let authToken: String
    private let configuredBaseURL: String
    private let cache: GLMQuotaCache
    private let client: GLMQuotaClient

    init(settings: AppSettings, cache: GLMQuotaCache, client: GLMQuotaClient = GLMQuotaClient()) {
        self.authToken = settings.glmAuthToken
        self.configuredBaseURL = settings.glmBaseURL
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
            UsageCard(id: .tokenUsage, title: "5 小时", systemImage: "gauge.with.dots.needle.bottom.50percent", primaryValue: token.map { "\($0.percentage)%" } ?? "N/A", trailingValue: token?.resetDateTimeText ?? "未返回重置", breakdown: nil, note: token?.usageText),
            UsageCard(id: .weeklyQuota, title: "7 天限额", systemImage: "calendar.badge.clock", primaryValue: weekly.map { "\($0.percentage)%" } ?? "N/A", trailingValue: "unit=6", breakdown: nil, note: weekly?.usageText ?? "新版套餐用户才会返回"),
            UsageCard(id: .mcpUsage, title: "MCP", systemImage: "point.3.connected.trianglepath.dotted", primaryValue: mcp.map { "\($0.percentage)%" } ?? "N/A", trailingValue: "TIME_LIMIT", breakdown: nil, note: mcp?.ratioText),
            UsageCard(id: .multiplier, title: "倍率", systemImage: "bolt.badge.clock", primaryValue: "API", trailingValue: stats.platformLabel, breakdown: nil, note: "内置读取 /monitor/usage/quota/limit")
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
                let decoded = try JSONDecoder().decode(GLMQuotaLimitResponse.self, from: data)
                guard decoded.success else {
                    throw ProviderError.commandFailed(decoded.msg)
                }
                return decoded.data.usageStats(platform: platform)
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

private struct GLMQuotaLimitResponse: Decodable {
    var code: Int?
    var msg: String
    var data: GLMQuotaLimitData
    var success: Bool
}

private struct GLMQuotaLimitData: Decodable {
    var limits: [GLMQuotaLimitItem]

    func usageStats(platform: GLMPlatform) -> GLMUsageStats {
        GLMUsageStats(
            platform: platform,
            tokenUsage: findQuota(type: "TOKENS_LIMIT", unit: 3, window: "5h"),
            weeklyUsage: findQuota(type: "TOKENS_LIMIT", unit: 6, window: "weekly"),
            mcpUsage: findQuota(type: "TIME_LIMIT", unit: nil, window: "30d")
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
