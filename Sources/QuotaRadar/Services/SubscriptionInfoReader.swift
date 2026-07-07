import Foundation

enum SubscriptionInfoResolver {
    static func resolve(automatic: SubscriptionInfo?, manualRule: ManualSubscriptionRule?, now: Date = Date()) -> SubscriptionInfo {
        if let automatic, automatic.targetDate != nil {
            return automatic
        }
        if let manualRule {
            return SubscriptionInfo(
                expiresAt: manualRule.nextDate(now: now),
                renewsAt: nil,
                planName: automatic?.planName ?? manualRule.displayText,
                source: .manual
            )
        }
        return .unavailable
    }
}

enum SubscriptionInfoParser {
    private static let expiryKeys = [
        "expires_at", "expiresAt", "expiration_time", "expirationTime", "expired_at", "expiredAt",
        "current_period_end", "currentPeriodEnd", "period_end", "periodEnd", "end_time", "endTime",
        "subscription_expires_at", "subscriptionExpiresAt", "plan_expires_at", "planExpiresAt"
    ]
    private static let renewalKeys = [
        "renewal_at", "renewalAt", "renews_at", "renewsAt", "renew_at", "renewAt",
        "next_billing_at", "nextBillingAt", "next_renewal_at", "nextRenewalAt",
        "current_period_renewal", "currentPeriodRenewal"
    ]
    private static let planKeys = [
        "plan_name", "planName", "plan", "plan_type", "planType", "subscription_plan",
        "subscriptionPlan", "product_name", "productName", "name", "title"
    ]

    static func parse(data: Data, source: SubscriptionInfoSource = .automatic) -> SubscriptionInfo? {
        guard let object = try? JSONSerialization.jsonObject(with: data) else {
            return nil
        }
        return parse(object, source: source)
    }

    static func parse(_ object: Any, source: SubscriptionInfoSource = .automatic) -> SubscriptionInfo? {
        let flattened = NumericKeyExtractor.flatten(object)
        let expiresAt = dateValue(flattened, keys: expiryKeys)
        let renewsAt = dateValue(flattened, keys: renewalKeys)
        let planName = stringValue(flattened, keys: planKeys)

        guard expiresAt != nil || renewsAt != nil || planName != nil else {
            return nil
        }

        return SubscriptionInfo(
            expiresAt: expiresAt,
            renewsAt: renewsAt,
            planName: planName,
            source: source
        )
    }

    private static func dateValue(_ values: [String: Any], keys: [String]) -> Date? {
        for key in keys {
            if let value = values[key], let date = parseDate(value) {
                return date
            }
            if let match = values.first(where: { $0.key.hasSuffix(".\(key)") })?.value,
               let date = parseDate(match) {
                return date
            }
        }
        return nil
    }

    private static func stringValue(_ values: [String: Any], keys: [String]) -> String? {
        for key in keys {
            if let value = values[key], let string = parseString(value) {
                return string
            }
            if let match = values.first(where: { $0.key.hasSuffix(".\(key)") })?.value,
               let string = parseString(match) {
                return string
            }
        }
        return nil
    }

    private static func parseDate(_ value: Any) -> Date? {
        if let string = value as? String {
            if let date = DateParser.parse(string) {
                return date
            }
            return TimeInterval(string).map(dateFromNumeric)
        }
        if let int = value as? Int {
            return dateFromNumeric(TimeInterval(int))
        }
        if let double = value as? Double {
            return dateFromNumeric(double)
        }
        return nil
    }

    private static func parseString(_ value: Any) -> String? {
        if let string = value as? String {
            let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : trimmed
        }
        if let number = value as? NSNumber {
            return number.stringValue
        }
        return nil
    }

    private static func dateFromNumeric(_ value: TimeInterval) -> Date {
        if value > 10_000_000_000 {
            return Date(timeIntervalSince1970: value / 1000)
        }
        return Date(timeIntervalSince1970: value)
    }
}

struct CodexSubscriptionReader: @unchecked Sendable {
    private let codexRoot: URL
    private let session: URLSession
    private let allowRemoteBackendLookup: Bool
    private let cache: SubscriptionInfoCache?
    private let cacheTTLSeconds: TimeInterval
    private let appServerReader: @Sendable () -> SubscriptionInfo?
    private let backendFetcher: (@Sendable () async throws -> SubscriptionInfo?)?

    init(
        codexRoot: URL,
        session: URLSession = .shared,
        allowRemoteBackendLookup: Bool = false,
        cache: SubscriptionInfoCache? = nil,
        cacheTTLSeconds: TimeInterval = 3_600,
        appServerReader: @escaping @Sendable () -> SubscriptionInfo? = { CodexAppServerSubscriptionReader().latestInfo() },
        backendFetcher: (@Sendable () async throws -> SubscriptionInfo?)? = nil
    ) {
        self.codexRoot = codexRoot
        self.session = session
        self.allowRemoteBackendLookup = allowRemoteBackendLookup
        self.cache = cache
        self.cacheTTLSeconds = cacheTTLSeconds
        self.appServerReader = appServerReader
        self.backendFetcher = backendFetcher
    }

    func subscriptionInfo(force: Bool = false) async -> SubscriptionInfo? {
        if !force, let cached = await cache?.current(ttlSeconds: cacheTTLSeconds) {
            return cached.info
        }

        let info = await fetchLiveSubscriptionInfo()
        await cache?.update(info)
        return info
    }

    private func fetchLiveSubscriptionInfo() async -> SubscriptionInfo? {
        if let info = appServerReader() {
            return info
        }

        guard allowRemoteBackendLookup else {
            return nil
        }
        if let backendFetcher {
            return try? await backendFetcher()
        }
        return try? await fetchBackendSubscriptionInfo()
    }

    private func fetchBackendSubscriptionInfo() async throws -> SubscriptionInfo? {
        let accessToken = try readAccessToken()
        let endpoints = [
            "https://chatgpt.com/backend-api/accounts/check/v4-2023-04-27",
            "https://chatgpt.com/backend-api/me"
        ]

        for endpoint in endpoints {
            guard let url = URL(string: endpoint) else { continue }
            var request = URLRequest(url: url)
            request.httpMethod = "GET"
            request.timeoutInterval = 5
            request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
            request.setValue("application/json", forHTTPHeaderField: "Accept")

            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
                continue
            }
            if let info = SubscriptionInfoParser.parse(data: data, source: .automatic) {
                return info
            }
        }
        return nil
    }

    private func readAccessToken() throws -> String {
        let authURL = codexRoot.appendingPathComponent("auth.json")
        let data = try Data(contentsOf: authURL)
        guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let tokens = object["tokens"] as? [String: Any],
              let accessToken = tokens["access_token"] as? String,
              !accessToken.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw ProviderError.missingCredentials("未找到 Codex access_token")
        }
        return accessToken
    }
}

struct SubscriptionInfoCacheEntry: Sendable {
    var info: SubscriptionInfo?
    var storedAt: Date
}

actor SubscriptionInfoCache {
    private var cached: SubscriptionInfoCacheEntry?

    func current(ttlSeconds: TimeInterval, now: Date = Date()) -> SubscriptionInfoCacheEntry? {
        guard let cached, now.timeIntervalSince(cached.storedAt) < ttlSeconds else {
            return nil
        }
        return cached
    }

    func update(_ info: SubscriptionInfo?, now: Date = Date()) {
        cached = SubscriptionInfoCacheEntry(info: info, storedAt: now)
    }
}

struct CodexAppServerSubscriptionReader: Sendable {
    func latestInfo() -> SubscriptionInfo? {
        guard let codexPath = CommandRunner.firstExecutable(candidates: [
            "/Applications/Codex.app/Contents/Resources/codex",
            "~/.codex/bin/codex",
            "~/.local/bin/codex",
            "~/.npm-global/bin/codex",
            "~/.bun/bin/codex",
            "~/.yarn/bin/codex",
            "/opt/homebrew/bin/codex",
            "/usr/local/bin/codex",
            "/usr/bin/codex"
        ], shellCommandNames: ["codex"]) else {
            return nil
        }

        let readMethods = [
            "account/subscription/read",
            "account/profile/read",
            "account/me/read"
        ]
        var requests: [[String: Any]] = [[
            "id": 1,
            "method": "initialize",
            "params": [
                "clientInfo": [
                    "name": "quota-radar",
                    "title": "Quota Radar",
                    "version": "1.0.3"
                ],
                "capabilities": [
                    "experimentalApi": true,
                    "optOutNotificationMethods": []
                ]
            ]
        ], ["method": "initialized"]]

        for (index, method) in readMethods.enumerated() {
            requests.append(["id": index + 3, "method": method])
        }

        let stdin = requests
            .compactMap { request -> String? in
                guard let data = try? JSONSerialization.data(withJSONObject: request) else { return nil }
                return String(data: data, encoding: .utf8)
            }
            .joined(separator: "\n") + "\n"

        guard let result = try? CommandRunner().run(codexPath, arguments: ["app-server"], stdin: stdin, timeout: 12, stdinCloseDelay: 2),
              result.status == 0 || !result.stdout.isEmpty else {
            return nil
        }

        for line in result.stdout.split(separator: "\n") {
            guard let data = String(line).data(using: .utf8),
                  let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let id = object["id"] as? Int,
                  id >= 3,
                  object["error"] == nil,
                  let payload = object["result"],
                  let info = SubscriptionInfoParser.parse(payload, source: .automatic) else {
                continue
            }
            return info
        }
        return nil
    }
}
