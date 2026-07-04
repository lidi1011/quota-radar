import Foundation

struct CodexProvider: UsageProvider, Sendable {
    let id: ProviderID = .codex
    private let home: URL

    init(home: URL = FileManager.default.homeDirectoryForCurrentUser) {
        self.home = home
    }

    func snapshot(force: Bool) async throws -> ProviderSnapshot {
        let codexRoot = home.appendingPathComponent(".codex")
        guard FileManager.default.fileExists(atPath: codexRoot.path) else {
            throw ProviderError.dataUnavailable("未找到 ~/.codex。请先安装并登录 Codex。")
        }

        let tokenEvents = CodexTokenLogReader(codexRoot: codexRoot).readEvents()
        let calendar = RadarFormatters.localCalendar
        let now = Date()
        let today = tokenEvents.aggregate(since: calendar.startOfDay(for: now))
        let sevenDays = tokenEvents.aggregate(since: calendar.date(byAdding: .day, value: -6, to: calendar.startOfDay(for: now)) ?? now)
        let month = tokenEvents.aggregate(since: calendar.startOfMonth(for: now))
        let total = tokenEvents.aggregate(since: .distantPast)
        let rateWindows = readRateLimitWindows(codexRoot: codexRoot)

        if tokenEvents.isEmpty && rateWindows.allSatisfy({ $0.resetText == "未连接" }) {
            throw ProviderError.dataUnavailable("Codex 本机数据存在，但没有可用的额度或 token 记录。请确认 Codex 至少运行过一次。")
        }

        let cards = [
            UsageCard(id: .today, title: "今日", systemImage: "sun.max.fill", primaryValue: RadarFormatters.compactTokens(today.breakdown.total), trailingValue: RadarFormatters.money(today.estimatedCostUSD), breakdown: today.breakdown, note: nil),
            UsageCard(id: .sevenDays, title: "近 7 天", systemImage: "calendar", primaryValue: RadarFormatters.compactTokens(sevenDays.breakdown.total), trailingValue: RadarFormatters.money(sevenDays.estimatedCostUSD), breakdown: sevenDays.breakdown, note: nil),
            UsageCard(id: .total, title: "累计", systemImage: "sum", primaryValue: RadarFormatters.compactTokens(total.breakdown.total), trailingValue: RadarFormatters.money(total.estimatedCostUSD), breakdown: total.breakdown, note: nil)
        ]

        return ProviderSnapshot(
            provider: .codex,
            generatedAt: Date(),
            windows: rateWindows,
            cards: cards,
            progress: PlanProgress.codex(value: month.estimatedCostUSD),
            statusMessage: "本机读取 ~/.codex 数据"
        )
    }

    private func readRateLimitWindows(codexRoot: URL) -> [UsageWindow] {
        if let snapshot = CodexAppServerRateLimitReader().latestSnapshot() {
            return snapshot.windows
        }

        if let snapshot = CodexRateLimitLogReader(codexRoot: codexRoot).latestSnapshot() {
            return snapshot.windows
        }

        return [
            .placeholder(id: "5h", label: "5 小时"),
            .placeholder(id: "7d", label: "7 天")
        ]
    }
}

struct CodexTokenEvent: Equatable, Sendable {
    var date: Date
    var breakdown: TokenBreakdown
    var estimatedCostUSD: Double
}

struct CodexUsageAggregate: Equatable, Sendable {
    var breakdown: TokenBreakdown
    var estimatedCostUSD: Double

    static let zero = CodexUsageAggregate(breakdown: .zero, estimatedCostUSD: 0)
}

struct CodexSessionSource: Equatable, Sendable {
    var file: URL
    var model: String?
}

struct CodexTokenLogReader: Sendable {
    var codexRoot: URL

    func readEvents() -> [CodexTokenEvent] {
        candidateSources().flatMap { source in
            readEvents(from: source)
        }
    }

    private func readEvents(from source: CodexSessionSource) -> [CodexTokenEvent] {
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: source.file.path),
              let fileSize = (attributes[.size] as? NSNumber)?.int64Value else {
            return []
        }

        let modificationDate = attributes[.modificationDate] as? Date
        let cacheKey = "\(source.file.path)\u{1f}\(source.model ?? "")"
        if let cached = CodexTokenEventCache.shared.events(
            key: cacheKey,
            fileSize: fileSize,
            modificationDate: modificationDate
        ) {
            return cached
        }

        let price = ModelTokenPrice.price(for: source.model)
        var previousTotal: TokenBreakdown?
        let events = tokenCountLines(from: source.file)
            .compactMap { line -> CodexTokenEvent? in
                if let totalEvent = CodexTokenParser.parseTotalLine(line, fileDate: fileDate(source.file)) {
                    let delta: TokenBreakdown
                    if let previousTotal {
                        let candidate = totalEvent.breakdown.delta(from: previousTotal)
                        delta = candidate.hasNegativeValue ? totalEvent.breakdown : candidate
                    } else {
                        delta = totalEvent.breakdown
                    }
                    previousTotal = totalEvent.breakdown
                    guard delta.total > 0 else { return nil }
                    return CodexTokenEvent(
                        date: totalEvent.date,
                        breakdown: delta,
                        estimatedCostUSD: delta.estimatedCostUSD(price: price)
                    )
                }

                guard let event = CodexTokenParser.parseLine(line, fileDate: fileDate(source.file), price: price) else {
                    return nil
                }
                return event
            }

        CodexTokenEventCache.shared.store(
            events,
            key: cacheKey,
            fileSize: fileSize,
            modificationDate: modificationDate
        )
        return events
    }

    private func tokenCountLines(from file: URL) -> [String] {
        if let lines = grepTokenCountLines(from: file) {
            return lines
        }

        guard let contents = try? String(contentsOf: file, encoding: .utf8) else {
            return []
        }
        return contents
            .split(separator: "\n")
            .map(String.init)
            .filter { $0.contains("token_count") }
    }

    private func grepTokenCountLines(from file: URL) -> [String]? {
        let grepPath = "/usr/bin/grep"
        guard FileManager.default.isExecutableFile(atPath: grepPath) else {
            return nil
        }

        do {
            let result = try CommandRunner().run(
                grepPath,
                arguments: ["-a", "-F", "token_count", file.path],
                timeout: 2
            )
            guard result.status == 0 || result.status == 1 else {
                return nil
            }
            return result.stdout.split(separator: "\n").map(String.init)
        } catch CommandRunnerError.timedOut {
            return []
        } catch {
            return nil
        }
    }

    private func candidateSources() -> [CodexSessionSource] {
        let sqliteSources = CodexSessionSourceReader(codexRoot: codexRoot).sources()
        if !sqliteSources.isEmpty {
            return sqliteSources
                .sorted { fileDate($0.file) > fileDate($1.file) }
                .map { $0 }
        }

        return candidateFiles()
            .map { CodexSessionSource(file: $0, model: nil) }
            .sorted { fileDate($0.file) > fileDate($1.file) }
            .map { $0 }
    }

    private func candidateFiles() -> [URL] {
        let roots = [
            codexRoot.appendingPathComponent("sessions"),
            codexRoot.appendingPathComponent("archived_sessions")
        ]
        let fileManager = FileManager.default
        var files: [URL] = []
        for root in roots where fileManager.fileExists(atPath: root.path) {
            guard let enumerator = fileManager.enumerator(at: root, includingPropertiesForKeys: [.contentModificationDateKey]) else { continue }
            for case let file as URL in enumerator where file.pathExtension == "jsonl" {
                files.append(file)
            }
        }
        return files
            .sorted { fileDate($0) > fileDate($1) }
            .map { $0 }
    }

    private func fileDate(_ file: URL) -> Date {
        (try? file.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
    }
}

final class CodexTokenEventCache: @unchecked Sendable {
    static let shared = CodexTokenEventCache()

    private struct Entry {
        var fileSize: Int64
        var modificationDate: Date?
        var events: [CodexTokenEvent]
    }

    private let lock = NSLock()
    private var storage: [String: Entry] = [:]

    func events(key: String, fileSize: Int64, modificationDate: Date?) -> [CodexTokenEvent]? {
        lock.lock()
        defer { lock.unlock() }
        guard let entry = storage[key],
              entry.fileSize == fileSize,
              entry.modificationDate == modificationDate else {
            return nil
        }
        return entry.events
    }

    func store(_ events: [CodexTokenEvent], key: String, fileSize: Int64, modificationDate: Date?) {
        lock.lock()
        storage[key] = Entry(fileSize: fileSize, modificationDate: modificationDate, events: events)
        lock.unlock()
    }
}

enum CodexTokenParser {
    static func parseLine(_ line: String, fileDate: Date, price: ModelTokenPrice = .defaultPrice) -> CodexTokenEvent? {
        guard line.contains("token_count"),
              let data = line.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) else {
            return nil
        }
        let flattened = NumericKeyExtractor.flatten(object)
        let usage = preferredUsageObject(from: object) ?? flattened
        let input = usage.firstValue(keys: ["input_tokens", "inputTokens", "input"])
        let cached = usage.firstValue(keys: ["cached_input_tokens", "cachedInputTokens", "cache_read_input_tokens", "cacheReadInputTokens", "cached"])
        let output = usage.firstValue(keys: ["output_tokens", "outputTokens", "output"])
        let rawTotal = usage.firstValue(keys: ["total_tokens", "totalTokens", "total"])
        let timestamp = flattened.stringValue(keys: ["timestamp", "ts", "created_at", "createdAt"])
        let date = timestamp.flatMap(DateParser.parse) ?? fileDate

        let uncached = max(0, input - cached)
        let breakdown = TokenBreakdown(uncachedInput: uncached, cachedInput: max(0, cached), output: max(0, output), rawTotal: max(0, rawTotal))
        return breakdown.total > 0 ? CodexTokenEvent(date: date, breakdown: breakdown, estimatedCostUSD: breakdown.estimatedCostUSD(price: price)) : nil
    }

    static func parseTotalLine(_ line: String, fileDate: Date) -> CodexTokenEvent? {
        guard line.contains("token_count"),
              let data = line.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data),
              let totalUsage = totalUsageObject(from: object) else {
            return nil
        }
        let flattened = NumericKeyExtractor.flatten(object)
        let input = totalUsage.firstValue(keys: ["input_tokens", "inputTokens", "input"])
        let cached = totalUsage.firstValue(keys: ["cached_input_tokens", "cachedInputTokens", "cache_read_input_tokens", "cacheReadInputTokens", "cached"])
        let output = totalUsage.firstValue(keys: ["output_tokens", "outputTokens", "output"])
        let rawTotal = totalUsage.firstValue(keys: ["total_tokens", "totalTokens", "total"])
        let timestamp = flattened.stringValue(keys: ["timestamp", "ts", "created_at", "createdAt"])
        let date = timestamp.flatMap(DateParser.parse) ?? fileDate
        let breakdown = TokenBreakdown(
            uncachedInput: max(0, input - cached),
            cachedInput: max(0, cached),
            output: max(0, output),
            rawTotal: max(0, rawTotal)
        )
        return breakdown.total > 0 ? CodexTokenEvent(date: date, breakdown: breakdown, estimatedCostUSD: 0) : nil
    }

    private static func preferredUsageObject(from object: Any) -> [String: Any]? {
        guard let root = object as? [String: Any] else { return nil }
        if let payload = root["payload"] as? [String: Any],
           let info = payload["info"] as? [String: Any] {
            if let last = info["last_token_usage"] as? [String: Any] {
                return last
            }
            if let last = info["lastTokenUsage"] as? [String: Any] {
                return last
            }
        }
        if let usage = root["usage"] as? [String: Any] {
            return usage
        }
        return nil
    }

    private static func totalUsageObject(from object: Any) -> [String: Any]? {
        guard let root = object as? [String: Any],
              let payload = root["payload"] as? [String: Any],
              let info = payload["info"] as? [String: Any] else {
            return nil
        }
        return info["total_token_usage"] as? [String: Any]
    }
}

struct CodexSessionSourceReader: Sendable {
    var codexRoot: URL

    func sources() -> [CodexSessionSource] {
        guard let dbPath = firstExistingPath([
            codexRoot.appendingPathComponent("state_5.sqlite").path,
            codexRoot.appendingPathComponent("sqlite/state_5.sqlite").path
        ]), let sqlitePath = firstExistingPath([
            "/usr/bin/sqlite3",
            "/opt/homebrew/bin/sqlite3",
            "/usr/local/bin/sqlite3"
        ]) else {
            return []
        }

        let query = """
        SELECT rollout_path, COALESCE(model, '')
        FROM threads
        WHERE rollout_path IS NOT NULL
          AND rollout_path <> ''
          AND tokens_used > 0
        ORDER BY updated_at DESC;
        """
        do {
            let result = try CommandRunner().run(
                sqlitePath,
                arguments: ["-readonly", "-separator", "\t", dbPath, query],
                timeout: 3
            )
            guard result.status == 0 else {
                return []
            }
            return parseSources(result.stdout)
        } catch {
            return []
        }
    }

    private func parseSources(_ text: String) -> [CodexSessionSource] {
        var seen = Set<String>()
        return text
            .split(separator: "\n")
            .compactMap { line -> CodexSessionSource? in
                let columns = line.split(separator: "\t", omittingEmptySubsequences: false)
                guard let rawPath = columns.first else { return nil }
                let path = String(rawPath)
                guard !path.isEmpty, seen.insert(path).inserted, FileManager.default.fileExists(atPath: path) else {
                    return nil
                }
                let model = columns.count > 1 ? String(columns[1]) : nil
                return CodexSessionSource(file: URL(fileURLWithPath: path), model: model?.isEmpty == false ? model : nil)
            }
    }

    private func firstExistingPath(_ paths: [String]) -> String? {
        paths.first { FileManager.default.fileExists(atPath: $0) || FileManager.default.isExecutableFile(atPath: $0) }
    }
}

struct CodexRateLimitSnapshot: Equatable, Sendable {
    var primaryUsedPercent: Double
    var primaryResetsAt: Date?
    var secondaryUsedPercent: Double
    var secondaryResetsAt: Date?
    var planType: String?

    var windows: [UsageWindow] {
        [
            UsageWindow(
                id: "5h",
                label: "5 小时",
                remainingPercent: max(0, 100 - primaryUsedPercent),
                usedPercent: primaryUsedPercent,
                resetText: primaryResetsAt.map(Self.resetText) ?? "未知"
            ),
            UsageWindow(
                id: "7d",
                label: "7 天",
                remainingPercent: max(0, 100 - secondaryUsedPercent),
                usedPercent: secondaryUsedPercent,
                resetText: secondaryResetsAt.map(Self.resetText) ?? "未知"
            )
        ]
    }

    private static func resetText(_ date: Date) -> String {
        RadarFormatters.resetDateTime(date)
    }
}

struct CodexAppServerRateLimitReader: Sendable {
    func latestSnapshot() -> CodexRateLimitSnapshot? {
        guard let codexPath = CommandRunner.firstExecutable(candidates: [
            "/Applications/Codex.app/Contents/Resources/codex",
            "~/.local/bin/codex",
            "/opt/homebrew/bin/codex",
            "/usr/local/bin/codex",
            "/usr/bin/codex"
        ]) else {
            return nil
        }
        let requests: [[String: Any]] = [[
            "id": 1,
            "method": "initialize",
            "params": [
                "clientInfo": [
                    "name": "quota-radar",
                    "title": "Quota Radar",
                    "version": "1.0.0"
                ],
                "capabilities": [
                    "experimentalApi": true,
                    "optOutNotificationMethods": []
                ]
            ]
        ],
        ["method": "initialized"],
        ["id": 3, "method": "account/rateLimits/read"]]

        let stdin = requests
            .compactMap { request -> String? in
                guard let data = try? JSONSerialization.data(withJSONObject: request) else { return nil }
                return String(data: data, encoding: .utf8)
            }
            .joined(separator: "\n") + "\n"

        guard let result = try? CommandRunner().run(codexPath, arguments: ["app-server"], stdin: stdin, timeout: 3),
              result.status == 0 || !result.stdout.isEmpty else {
            return nil
        }

        for line in result.stdout.split(separator: "\n") {
            guard let data = String(line).data(using: .utf8),
                  let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  object["id"] as? Int == 3,
                  let payload = object["result"] as? [String: Any],
                  let snapshot = CodexAppServerRateLimitParser.parse(payload) else {
                continue
            }
            return snapshot
        }
        return nil
    }
}

enum CodexAppServerRateLimitParser {
    static func parse(_ result: [String: Any]) -> CodexRateLimitSnapshot? {
        let selected: [String: Any]?
        if let byId = result["rateLimitsByLimitId"] as? [String: Any],
           let codex = byId["codex"] as? [String: Any] {
            selected = codex
        } else {
            selected = result["rateLimits"] as? [String: Any]
        }

        guard let limits = selected else { return nil }
        return CodexRateLimitSnapshot(
            primaryUsedPercent: parseWindow(limits["primary"])?.usedPercent ?? 0,
            primaryResetsAt: parseWindow(limits["primary"])?.resetsAt,
            secondaryUsedPercent: parseWindow(limits["secondary"])?.usedPercent ?? 0,
            secondaryResetsAt: parseWindow(limits["secondary"])?.resetsAt,
            planType: limits["limitName"] as? String ?? limits["limitId"] as? String
        )
    }

    private static func parseWindow(_ value: Any?) -> (usedPercent: Double, resetsAt: Date?)? {
        guard let object = value as? [String: Any],
              let used = doubleValue(object["usedPercent"]) else {
            return nil
        }
        let reset = doubleValue(object["resetsAt"]).map { Date(timeIntervalSince1970: $0) }
        return (used, reset)
    }
}

struct CodexRateLimitLogReader: Sendable {
    var codexRoot: URL

    func latestSnapshot() -> CodexRateLimitSnapshot? {
        for file in candidateFiles() {
            guard let contents = try? String(contentsOf: file, encoding: .utf8) else {
                continue
            }
            for line in contents.split(separator: "\n").reversed() {
                if let snapshot = CodexRateLimitParser.parseLine(String(line)) {
                    return snapshot
                }
            }
        }
        return nil
    }

    private func candidateFiles() -> [URL] {
        let roots = [
            codexRoot.appendingPathComponent("sessions"),
            codexRoot.appendingPathComponent("archived_sessions")
        ]
        let fileManager = FileManager.default
        var files: [URL] = []
        for root in roots where fileManager.fileExists(atPath: root.path) {
            guard let enumerator = fileManager.enumerator(at: root, includingPropertiesForKeys: [.contentModificationDateKey]) else { continue }
            for case let file as URL in enumerator where file.pathExtension == "jsonl" {
                files.append(file)
            }
        }
        return files
            .sorted { fileDate($0) > fileDate($1) }
            .prefix(200)
            .map { $0 }
    }

    private func fileDate(_ file: URL) -> Date {
        (try? file.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
    }
}

enum CodexRateLimitParser {
    static func parseLine(_ line: String) -> CodexRateLimitSnapshot? {
        guard line.contains(#""rate_limits""#),
              let data = line.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) else {
            return nil
        }
        let values = NumericKeyExtractor.flatten(object)
        let primaryUsed = Double(values.firstValue(keys: ["rate_limits.primary.used_percent", "primary.used_percent"]))
        let primaryReset = values.firstValue(keys: ["rate_limits.primary.resets_at", "primary.resets_at"])
        let secondaryUsed = Double(values.firstValue(keys: ["rate_limits.secondary.used_percent", "secondary.used_percent"]))
        let secondaryReset = values.firstValue(keys: ["rate_limits.secondary.resets_at", "secondary.resets_at"])
        let planType = values.stringValue(keys: ["rate_limits.plan_type", "plan_type"])

        guard primaryUsed > 0 || secondaryUsed > 0 || primaryReset > 0 || secondaryReset > 0 else {
            return nil
        }

        return CodexRateLimitSnapshot(
            primaryUsedPercent: primaryUsed,
            primaryResetsAt: primaryReset > 0 ? Date(timeIntervalSince1970: TimeInterval(primaryReset)) : nil,
            secondaryUsedPercent: secondaryUsed,
            secondaryResetsAt: secondaryReset > 0 ? Date(timeIntervalSince1970: TimeInterval(secondaryReset)) : nil,
            planType: planType
        )
    }
}

extension Array where Element == CodexTokenEvent {
    func aggregate(since date: Date) -> CodexUsageAggregate {
        reduce(.zero) { partial, event in
            guard event.date >= date else { return partial }
            return CodexUsageAggregate(
                breakdown: TokenBreakdown(
                    uncachedInput: partial.breakdown.uncachedInput + event.breakdown.uncachedInput,
                    cachedInput: partial.breakdown.cachedInput + event.breakdown.cachedInput,
                    output: partial.breakdown.output + event.breakdown.output,
                    rawTotal: partial.breakdown.rawTotal + event.breakdown.rawTotal
                ),
                estimatedCostUSD: partial.estimatedCostUSD + event.estimatedCostUSD
            )
        }
    }
}

extension TokenBreakdown {
    var hasNegativeValue: Bool {
        uncachedInput < 0 || cachedInput < 0 || output < 0 || rawTotal < 0
    }

    func delta(from previous: TokenBreakdown) -> TokenBreakdown {
        TokenBreakdown(
            uncachedInput: uncachedInput - previous.uncachedInput,
            cachedInput: cachedInput - previous.cachedInput,
            output: output - previous.output,
            rawTotal: rawTotal - previous.rawTotal
        )
    }

    func estimatedCostUSD(price: ModelTokenPrice) -> Double {
        Double(max(uncachedInput, 0)) / 1_000_000 * price.inputPerMillion
            + Double(max(cachedInput, 0)) / 1_000_000 * price.cachedInputPerMillion
            + Double(max(output, 0)) / 1_000_000 * price.outputPerMillion
    }

    var apiEquivalentValue: Double {
        estimatedCostUSD(price: .defaultPrice)
    }
}

struct ModelTokenPrice: Equatable, Sendable {
    var model: String
    var inputPerMillion: Double
    var cachedInputPerMillion: Double
    var outputPerMillion: Double

    static let defaultPrice = ModelTokenPrice(model: "gpt-5.5", inputPerMillion: 5, cachedInputPerMillion: 0.5, outputPerMillion: 30)

    static func price(for model: String?) -> ModelTokenPrice {
        let normalized = (model ?? "").lowercased()
        if normalized.contains("gpt-5.5-pro") {
            return ModelTokenPrice(model: "gpt-5.5-pro", inputPerMillion: 30, cachedInputPerMillion: 30, outputPerMillion: 180)
        }
        if normalized.contains("gpt-5.5") || normalized == "chat-latest" {
            return .defaultPrice
        }
        if normalized.contains("gpt-5.4-mini") {
            return ModelTokenPrice(model: "gpt-5.4-mini", inputPerMillion: 0.75, cachedInputPerMillion: 0.075, outputPerMillion: 4.5)
        }
        if normalized.contains("gpt-5.4-nano") {
            return ModelTokenPrice(model: "gpt-5.4-nano", inputPerMillion: 0.2, cachedInputPerMillion: 0.02, outputPerMillion: 1.25)
        }
        if normalized.contains("gpt-5.4-pro") {
            return ModelTokenPrice(model: "gpt-5.4-pro", inputPerMillion: 30, cachedInputPerMillion: 30, outputPerMillion: 180)
        }
        if normalized.contains("gpt-5.4") {
            return ModelTokenPrice(model: "gpt-5.4", inputPerMillion: 2.5, cachedInputPerMillion: 0.25, outputPerMillion: 15)
        }
        if normalized.contains("gpt-5.3-codex")
            || normalized.contains("gpt-5.2-codex")
            || normalized.contains("gpt-5.3-chat")
            || normalized.contains("gpt-5.2") {
            return ModelTokenPrice(model: "gpt-5.2-codex", inputPerMillion: 1.75, cachedInputPerMillion: 0.175, outputPerMillion: 14)
        }
        if normalized.contains("gpt-5-codex") || normalized == "gpt-5" {
            return ModelTokenPrice(model: "gpt-5", inputPerMillion: 1.25, cachedInputPerMillion: 0.125, outputPerMillion: 10)
        }
        return .defaultPrice
    }
}

private extension Calendar {
    func startOfMonth(for date: Date) -> Date {
        var components = dateComponents([.year, .month], from: date)
        components.day = 1
        components.hour = 0
        components.minute = 0
        components.second = 0
        return self.date(from: components) ?? startOfDay(for: date)
    }
}

private func doubleValue(_ value: Any?) -> Double? {
    if let double = value as? Double { return double }
    if let int = value as? Int { return Double(int) }
    if let number = value as? NSNumber { return number.doubleValue }
    if let string = value as? String { return Double(string) }
    return nil
}

extension PlanProgress {
    static let codexMonthlyMaxUSD: Double = {
        let dailyTokenLimit = 200_000_000.0
        let billingDays = 30.0
        let referencePrice = ModelTokenPrice.price(for: "chat-latest")
        let weightedPricePerMillion = 0.30 * referencePrice.inputPerMillion
            + 0.50 * referencePrice.cachedInputPerMillion
            + 0.20 * referencePrice.outputPerMillion
        return dailyTokenLimit * billingDays / 1_000_000 * weightedPricePerMillion
    }()

    static let codexMarkers = [
        PlanMarker(id: "plus", label: "Plus", position: codexProgressPosition(for: 20)),
        PlanMarker(id: "pro100", label: "Pro100", position: codexProgressPosition(for: 100)),
        PlanMarker(id: "pro200", label: "Pro200", position: codexProgressPosition(for: 200))
    ]

    static func codex(value: Double) -> PlanProgress {
        PlanProgress(
            title: "羊毛进度",
            currentValue: RadarFormatters.money(value),
            maxValue: "$46.5K",
            progress: codexProgressPosition(for: value),
            markers: codexMarkers
        )
    }

    private static func codexProgressPosition(for amount: Double) -> Double {
        let subscriptionCeiling = 200.0
        let subscriptionBand = 0.28
        let clamped = max(0, min(amount, codexMonthlyMaxUSD))
        if clamped <= subscriptionCeiling {
            return subscriptionBand * (clamped / subscriptionCeiling)
        }

        let remainingValue = max(codexMonthlyMaxUSD - subscriptionCeiling, 1)
        return subscriptionBand + (1 - subscriptionBand) * ((clamped - subscriptionCeiling) / remainingValue)
    }
}
