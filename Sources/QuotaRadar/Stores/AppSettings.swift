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

    func isProviderVisible(_ provider: ProviderID) -> Bool {
        preferences(for: provider).isVisible
    }

    func setProviderVisible(_ visible: Bool, provider: ProviderID) {
        var preference = preferences(for: provider)
        preference.isVisible = visible
        updatePreferences(preference, for: provider)
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
    var isVisible: Bool
    var ringPrimaryHex: String
    var ringSecondaryHex: String
    var cardAccentHex: String
    var visibleCards: Set<UsageCardID>

    init(isVisible: Bool = true, ringPrimaryHex: String, ringSecondaryHex: String, cardAccentHex: String, visibleCards: Set<UsageCardID>) {
        self.isVisible = isVisible
        self.ringPrimaryHex = ringPrimaryHex
        self.ringSecondaryHex = ringSecondaryHex
        self.cardAccentHex = cardAccentHex
        self.visibleCards = visibleCards
    }

    private enum CodingKeys: String, CodingKey {
        case isVisible
        case ringPrimaryHex
        case ringSecondaryHex
        case cardAccentHex
        case visibleCards
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        isVisible = try container.decodeIfPresent(Bool.self, forKey: .isVisible) ?? true
        ringPrimaryHex = try container.decode(String.self, forKey: .ringPrimaryHex)
        ringSecondaryHex = try container.decode(String.self, forKey: .ringSecondaryHex)
        cardAccentHex = try container.decode(String.self, forKey: .cardAccentHex)
        visibleCards = try container.decode(Set<UsageCardID>.self, forKey: .visibleCards)
    }

    static func defaults(for provider: ProviderID) -> ProviderPreferences {
        switch provider {
        case .codex:
            ProviderPreferences(
                ringPrimaryHex: "#1E88FF",
                ringSecondaryHex: "#8B5CF6",
                cardAccentHex: "#2563EB",
                visibleCards: [.today, .sevenDays, .total, .planProgress, .resetCredits]
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
        if provider == .codex, !defaults.bool(forKey: Keys.codexResetCreditsMigrated) {
            var migrated = decoded
            migrated.visibleCards.insert(.resetCredits)
            migrated.save(provider: provider, defaults: defaults)
            defaults.set(true, forKey: Keys.codexResetCreditsMigrated)
            return migrated
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
    static let codexResetCreditsMigrated = "providerPreferences.codex.resetCreditsMigrated"

    static func provider(_ provider: ProviderID) -> String {
        "providerPreferences.\(provider.rawValue)"
    }
}
