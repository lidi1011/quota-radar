import Foundation

final class AppSettings: ObservableObject {
    @Published var refreshIntervalMinutes: Double {
        didSet { defaults.set(refreshIntervalMinutes, forKey: Keys.refreshIntervalMinutes) }
    }

    @Published var providerPreferences: [ProviderID: ProviderPreferences] {
        didSet { saveProviderPreferences() }
    }

    @Published var glmAuthToken: String {
        didSet { defaults.set(glmAuthToken, forKey: Keys.glmAuthToken) }
    }

    @Published var glmBaseURL: String {
        didSet { defaults.set(glmBaseURL, forKey: Keys.glmBaseURL) }
    }

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let savedInterval = defaults.double(forKey: Keys.refreshIntervalMinutes)
        refreshIntervalMinutes = savedInterval > 0 ? savedInterval : 5
        glmAuthToken = defaults.string(forKey: Keys.glmAuthToken) ?? ""
        glmBaseURL = defaults.string(forKey: Keys.glmBaseURL) ?? "https://open.bigmodel.cn/api/anthropic"
        providerPreferences = ProviderID.allCases.reduce(into: [:]) { result, provider in
            result[provider] = ProviderPreferences.load(provider: provider, defaults: defaults)
        }
    }

    func preferences(for provider: ProviderID) -> ProviderPreferences {
        providerPreferences[provider] ?? ProviderPreferences.defaults(for: provider)
    }

    func updatePreferences(_ preferences: ProviderPreferences, for provider: ProviderID) {
        providerPreferences[provider] = preferences
    }

    func isVisible(_ card: UsageCardID, for provider: ProviderID) -> Bool {
        preferences(for: provider).visibleCards.contains(card)
    }

    func setVisible(_ visible: Bool, card: UsageCardID, provider: ProviderID) {
        var preference = preferences(for: provider)
        if visible {
            preference.visibleCards.insert(card)
        } else {
            preference.visibleCards.remove(card)
        }
        updatePreferences(preference, for: provider)
    }

    private func saveProviderPreferences() {
        for (provider, preferences) in providerPreferences {
            preferences.save(provider: provider, defaults: defaults)
        }
    }
}

struct ProviderPreferences: Codable, Equatable {
    var ringPrimaryHex: String
    var ringSecondaryHex: String
    var cardAccentHex: String
    var visibleCards: Set<UsageCardID>

    static func defaults(for provider: ProviderID) -> ProviderPreferences {
        switch provider {
        case .codex:
            ProviderPreferences(
                ringPrimaryHex: "#1E88FF",
                ringSecondaryHex: "#8B5CF6",
                cardAccentHex: "#2563EB",
                visibleCards: [.today, .sevenDays, .total, .planProgress]
            )
        case .glm:
            ProviderPreferences(
                ringPrimaryHex: "#14B8A6",
                ringSecondaryHex: "#F97316",
                cardAccentHex: "#10B981",
                visibleCards: [.tokenUsage, .weeklyQuota, .mcpUsage, .multiplier]
            )
        }
    }

    static func load(provider: ProviderID, defaults: UserDefaults) -> ProviderPreferences {
        guard let data = defaults.data(forKey: Keys.provider(provider)),
              let decoded = try? JSONDecoder().decode(ProviderPreferences.self, from: data) else {
            return .defaults(for: provider)
        }
        return decoded
    }

    func save(provider: ProviderID, defaults: UserDefaults) {
        guard let data = try? JSONEncoder().encode(self) else { return }
        defaults.set(data, forKey: Keys.provider(provider))
    }
}

private enum Keys {
    static let refreshIntervalMinutes = "refreshIntervalMinutes"
    static let glmAuthToken = "glmAuthToken"
    static let glmBaseURL = "glmBaseURL"

    static func provider(_ provider: ProviderID) -> String {
        "providerPreferences.\(provider.rawValue)"
    }
}
