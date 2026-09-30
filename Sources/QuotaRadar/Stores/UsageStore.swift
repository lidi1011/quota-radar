import Foundation

@MainActor
final class UsageStore: ObservableObject {
    @Published private(set) var snapshots: [ProviderID: ProviderSnapshot] = [:]
    @Published private(set) var states: [ProviderID: ProviderLoadState] = [
        .codex: .idle,
        .glm: .idle,
        .claude: .idle
    ]

    private let settings: AppSettings
    private let claudeDesktopClient: ClaudeDesktopClient
    private var refreshVersions: [ProviderID: UUID] = [:]
    private let glmCache = GLMQuotaCache()
    private let codexSubscriptionCache = SubscriptionInfoCache()
    private var timer: Timer?

    init(settings: AppSettings, claudeDesktopClient: ClaudeDesktopClient = ClaudeDesktopClient()) {
        self.settings = settings
        self.claudeDesktopClient = claudeDesktopClient
    }

    func startAutoRefresh() {
        timer?.invalidate()
        let interval = max(60, settings.refreshIntervalMinutes * 60)
        timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            Task { @MainActor in
                await self?.refreshAll(force: false)
            }
        }
    }

    func stopAutoRefresh() {
        timer?.invalidate()
        timer = nil
    }

    func refreshAll(force: Bool) async {
        let providers = ProviderID.allCases.map { provider in
            (id: provider, provider: makeProvider(provider), version: beginRefresh(provider))
        }
        for item in providers {
            states[item.id] = .loading
        }

        await withTaskGroup(of: RefreshOutcome.self) { group in
            for item in providers {
                group.addTask {
                    do {
                        return .success(item.id, item.version, try await item.provider.snapshot(force: force))
                    } catch {
                        return .failure(item.id, item.version, error.localizedDescription)
                    }
                }
            }

            for await outcome in group {
                apply(outcome)
            }
        }
    }

    func refresh(_ provider: ProviderID, force: Bool = true) async {
        let version = beginRefresh(provider)
        states[provider] = .loading
        do {
            apply(.success(provider, version, try await makeProvider(provider).snapshot(force: force)))
        } catch {
            apply(.failure(provider, version, error.localizedDescription))
        }
    }

    // Invalidate immediately when the source changes, before starting another task.
    func changeClaudeSource() {
        refreshVersions[.claude] = UUID()
        snapshots[.claude] = ClaudeCodeProvider.unavailable(settings.claudeReadingEnabled
            ? "正在读取 \(settings.claudeQuotaSource.title) 额度" : claudePausedMessage)
        if !settings.claudeReadingEnabled { states[.claude] = .idle }
        Task {
            if settings.claudeQuotaSource == .cli || !settings.claudeDesktopReadingEnabled {
                await claudeDesktopClient.cancelPending()
            }
            if settings.claudeReadingEnabled { await refresh(.claude) }
        }
    }

    private var claudePausedMessage: String {
        "\(settings.claudeQuotaSource.title) · 已暂停读取"
    }

    private func beginRefresh(_ provider: ProviderID) -> UUID {
        let version = UUID()
        if provider == .claude && settings.claudeQuotaSource == .desktop && settings.claudeReadingEnabled {
            snapshots[.claude] = ClaudeCodeProvider.unavailable("正在核对 Claude 桌面端账号与额度")
        }
        refreshVersions[provider] = version
        return version
    }

    private func makeProvider(_ provider: ProviderID) -> UsageProvider {
        switch provider {
        case .codex:
            CodexProvider(
                manualSubscriptionRule: settings.codexManualSubscriptionRule,
                allowRemoteSubscriptionLookup: settings.codexRemoteSubscriptionLookupEnabled,
                subscriptionCache: codexSubscriptionCache
            )
        case .claude:
            if !settings.claudeReadingEnabled {
                PausedClaudeProvider(message: claudePausedMessage)
            } else {
                settings.claudeQuotaSource == .cli ? ClaudeCodeProvider() as any UsageProvider : ClaudeDesktopProvider(client: claudeDesktopClient) as any UsageProvider
            }
        case .glm:
            GLMProvider(settings: settings, cache: glmCache)
        }
    }

    private func manualSubscriptionRule(for provider: ProviderID) -> ManualSubscriptionRule? {
        switch provider {
        case .codex:
            settings.codexManualSubscriptionRule
        case .claude:
            nil
        case .glm:
            settings.glmManualSubscriptionRule
        }
    }

    private func apply(_ outcome: RefreshOutcome) {
        switch outcome {
        case .success(let provider, let version, let snapshot):
            guard refreshVersions[provider] == version else { return }
            if provider == .claude && !settings.claudeReadingEnabled {
                snapshots[.claude] = ClaudeCodeProvider.unavailable(claudePausedMessage)
                states[.claude] = .idle
                return
            }
            snapshots[provider] = snapshot
            states[provider] = .loaded(Date())
        case .failure(let provider, let version, let message):
            guard refreshVersions[provider] == version else { return }
            if provider == .claude && !settings.claudeReadingEnabled {
                snapshots[.claude] = ClaudeCodeProvider.unavailable(claudePausedMessage)
                states[.claude] = .idle
                return
            }
            states[provider] = .failed(message)
            snapshots[provider] = ProviderSnapshot.placeholder(
                provider: provider,
                message: message,
                manualSubscriptionRule: manualSubscriptionRule(for: provider)
            )
        }
    }
}

private struct PausedClaudeProvider: UsageProvider {
    let id: ProviderID = .claude
    let message: String
    func snapshot(force: Bool) async throws -> ProviderSnapshot {
        ClaudeCodeProvider.unavailable(message)
    }
}

private enum RefreshOutcome: Sendable {
    case success(ProviderID, UUID, ProviderSnapshot)
    case failure(ProviderID, UUID, String)
}

private extension ProviderSnapshot {
    static func placeholder(provider: ProviderID, message: String, manualSubscriptionRule: ManualSubscriptionRule? = nil) -> ProviderSnapshot {
        let cards: [UsageCard]
        let windows: [UsageWindow]
        let progress: PlanProgress?
        let subscriptionCard = SubscriptionInfoResolver
            .resolve(automatic: nil, manualRule: manualSubscriptionRule)
            .usageCard()

        switch provider {
        case .claude:
            return ClaudeCodeProvider.unavailable(message)
        case .codex:
            windows = [
                .placeholder(id: "5h", label: "5 小时"),
                .placeholder(id: "7d", label: "7 天")
            ]
            cards = [
                UsageCard(id: .today, title: "今日", systemImage: "sun.max.fill", primaryValue: "0", trailingValue: "$0.00", breakdown: .zero, note: message),
                UsageCard(id: .sevenDays, title: "近 7 天", systemImage: "calendar", primaryValue: "0", trailingValue: "$0.00", breakdown: .zero, note: nil),
                UsageCard(id: .total, title: "累计", systemImage: "sum", primaryValue: "0", trailingValue: "$0.00", breakdown: .zero, note: nil),
                UsageCard(id: .resetCredits, title: "重置次数", systemImage: "arrow.counterclockwise.circle", primaryValue: "--", trailingValue: "", breakdown: nil, note: message),
                subscriptionCard
            ]
            progress = PlanProgress(title: "羊毛进度", currentValue: "$0.00", maxValue: "$46.5K", progress: 0, markers: PlanProgress.codexMarkers)
        case .glm:
            windows = [
                .placeholder(id: "token", label: "5 小时"),
                .placeholder(id: "weekly", label: "7 天")
            ]
            cards = [
                UsageCard(id: .tokenUsage, title: "5 小时", systemImage: "gauge.with.dots.needle.bottom.50percent", primaryValue: "0%", trailingValue: "未连接", breakdown: nil, note: message),
                UsageCard(id: .weeklyQuota, title: "7 天限额", systemImage: "calendar.badge.clock", primaryValue: "0%", trailingValue: "新版套餐", breakdown: nil, note: nil),
                UsageCard(id: .mcpUsage, title: "MCP", systemImage: "point.3.connected.trianglepath.dotted", primaryValue: "0%", trailingValue: "工具调用", breakdown: nil, note: nil),
                UsageCard(id: .multiplier, title: "倍率", systemImage: "bolt.badge.clock", primaryValue: GLMMultiplierCalculator.currentInfo().displayValue, trailingValue: "premium", breakdown: nil, note: message),
                subscriptionCard
            ]
            progress = nil
        }

        return ProviderSnapshot(provider: provider, generatedAt: Date(), windows: windows, cards: cards, progress: progress, statusMessage: message)
    }
}
