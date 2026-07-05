import Foundation

@MainActor
final class UsageStore: ObservableObject {
    @Published private(set) var snapshots: [ProviderID: ProviderSnapshot] = [:]
    @Published private(set) var states: [ProviderID: ProviderLoadState] = [
        .codex: .idle,
        .glm: .idle
    ]

    private let settings: AppSettings
    private let glmCache = GLMQuotaCache()
    private var timer: Timer?

    init(settings: AppSettings) {
        self.settings = settings
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
            (id: provider, provider: makeProvider(provider))
        }
        for item in providers {
            states[item.id] = .loading
        }

        await withTaskGroup(of: RefreshOutcome.self) { group in
            for item in providers {
                group.addTask {
                    do {
                        return .success(item.id, try await item.provider.snapshot(force: force))
                    } catch {
                        return .failure(item.id, error.localizedDescription)
                    }
                }
            }

            for await outcome in group {
                apply(outcome)
            }
        }
    }

    func refresh(_ provider: ProviderID, force: Bool = true) async {
        states[provider] = .loading
        do {
            let snapshot = try await makeProvider(provider).snapshot(force: force)
            snapshots[provider] = snapshot
            states[provider] = .loaded(Date())
        } catch {
            states[provider] = .failed(error.localizedDescription)
            snapshots[provider] = ProviderSnapshot.placeholder(provider: provider, message: error.localizedDescription)
        }
    }

    private func makeProvider(_ provider: ProviderID) -> UsageProvider {
        switch provider {
        case .codex:
            CodexProvider()
        case .glm:
            GLMProvider(settings: settings, cache: glmCache)
        }
    }

    private func apply(_ outcome: RefreshOutcome) {
        switch outcome {
        case .success(let provider, let snapshot):
            snapshots[provider] = snapshot
            states[provider] = .loaded(Date())
        case .failure(let provider, let message):
            states[provider] = .failed(message)
            snapshots[provider] = ProviderSnapshot.placeholder(provider: provider, message: message)
        }
    }
}

private enum RefreshOutcome: Sendable {
    case success(ProviderID, ProviderSnapshot)
    case failure(ProviderID, String)
}

private extension ProviderSnapshot {
    static func placeholder(provider: ProviderID, message: String) -> ProviderSnapshot {
        let cards: [UsageCard]
        let windows: [UsageWindow]
        let progress: PlanProgress?

        switch provider {
        case .codex:
            windows = [
                .placeholder(id: "5h", label: "5 小时"),
                .placeholder(id: "7d", label: "7 天")
            ]
            cards = [
                UsageCard(id: .today, title: "今日", systemImage: "sun.max.fill", primaryValue: "0", trailingValue: "$0.00", breakdown: .zero, note: message),
                UsageCard(id: .sevenDays, title: "近 7 天", systemImage: "calendar", primaryValue: "0", trailingValue: "$0.00", breakdown: .zero, note: nil),
                UsageCard(id: .total, title: "累计", systemImage: "sum", primaryValue: "0", trailingValue: "$0.00", breakdown: .zero, note: nil),
                UsageCard(id: .resetCredits, title: "重置次数", systemImage: "arrow.counterclockwise.circle", primaryValue: "--", trailingValue: "", breakdown: nil, note: message)
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
                UsageCard(id: .mcpUsage, title: "MCP", systemImage: "point.3.connected.trianglepath.dotted", primaryValue: "0/0", trailingValue: "工具调用", breakdown: nil, note: nil),
                UsageCard(id: .multiplier, title: "倍率", systemImage: "bolt.badge.clock", primaryValue: GLMMultiplierCalculator.currentInfo().displayValue, trailingValue: "premium", breakdown: nil, note: message)
            ]
            progress = nil
        }

        return ProviderSnapshot(provider: provider, generatedAt: Date(), windows: windows, cards: cards, progress: progress, statusMessage: message)
    }
}
