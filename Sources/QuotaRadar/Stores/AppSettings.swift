import Foundation

final class AppSettings: ObservableObject {
    @Published var refreshIntervalMinutes: Double {
        didSet { defaults.set(refreshIntervalMinutes, forKey: Keys.refreshIntervalMinutes) }
    }

    @Published var providerPreferences: [ProviderID: ProviderPreferences] {
        didSet { saveProviderPreferences() }
    }

    @Published var layoutPreset: LayoutPreset {
        didSet { defaults.set(layoutPreset.rawValue, forKey: Keys.layoutPreset) }
    }

    @Published var providerLayoutMode: ProviderLayoutMode {
        didSet { defaults.set(providerLayoutMode.rawValue, forKey: Keys.providerLayoutMode) }
    }

    @Published var codexQuotaRingMode: CodexQuotaRingMode {
        didSet { defaults.set(codexQuotaRingMode.rawValue, forKey: Keys.codexQuotaRingMode) }
    }

    @Published var glmAuthToken: String {
        didSet { defaults.set(glmAuthToken, forKey: Keys.glmAuthToken) }
    }

    @Published var glmBaseURL: String {
        didSet { defaults.set(glmBaseURL, forKey: Keys.glmBaseURL) }
    }

    @Published var codexManualSubscriptionRule: ManualSubscriptionRule? {
        didSet { saveOptionalRule(codexManualSubscriptionRule, key: Keys.codexManualSubscriptionRule) }
    }

    @Published var codexRemoteSubscriptionLookupEnabled: Bool {
        didSet { defaults.set(codexRemoteSubscriptionLookupEnabled, forKey: Keys.codexRemoteSubscriptionLookupEnabled) }
    }

    @Published var glmManualSubscriptionRule: ManualSubscriptionRule? {
        didSet { saveOptionalRule(glmManualSubscriptionRule, key: Keys.glmManualSubscriptionRule) }
    }

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let savedInterval = defaults.double(forKey: Keys.refreshIntervalMinutes)
        refreshIntervalMinutes = savedInterval > 0 ? savedInterval : 5
        layoutPreset = defaults.string(forKey: Keys.layoutPreset).flatMap(LayoutPreset.init(rawValue:)) ?? .standard
        providerLayoutMode = defaults.string(forKey: Keys.providerLayoutMode).flatMap(ProviderLayoutMode.init(rawValue:)) ?? .vertical
        codexQuotaRingMode = defaults.string(forKey: Keys.codexQuotaRingMode).flatMap(CodexQuotaRingMode.init(rawValue:)) ?? .sevenDay
        glmAuthToken = defaults.string(forKey: Keys.glmAuthToken) ?? ""
        glmBaseURL = defaults.string(forKey: Keys.glmBaseURL) ?? "https://open.bigmodel.cn/api/anthropic"
        codexRemoteSubscriptionLookupEnabled = defaults.bool(forKey: Keys.codexRemoteSubscriptionLookupEnabled)
        codexManualSubscriptionRule = Self.loadManualSubscriptionRule(
            provider: .codex,
            ruleKey: Keys.codexManualSubscriptionRule,
            legacyDateKey: Keys.codexManualSubscriptionExpiry,
            defaults: defaults
        )
        glmManualSubscriptionRule = Self.loadManualSubscriptionRule(
            provider: .glm,
            ruleKey: Keys.glmManualSubscriptionRule,
            legacyDateKey: Keys.glmManualSubscriptionExpiry,
            defaults: defaults
        )
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

    private func saveOptionalRule(_ rule: ManualSubscriptionRule?, key: String) {
        if let rule, let data = try? JSONEncoder().encode(rule) {
            defaults.set(data, forKey: key)
        } else {
            defaults.removeObject(forKey: key)
        }
    }

    private static func loadManualSubscriptionRule(provider: ProviderID, ruleKey: String, legacyDateKey: String, defaults: UserDefaults) -> ManualSubscriptionRule? {
        if let data = defaults.data(forKey: ruleKey),
           let rule = try? JSONDecoder().decode(ManualSubscriptionRule.self, from: data) {
            return rule
        }

        guard let legacyDate = defaults.object(forKey: legacyDateKey) as? Date else {
            return nil
        }
        let day = RadarFormatters.localCalendar.component(.day, from: legacyDate)
        let migrated = ManualSubscriptionRule.monthly(day: day)
        if let data = try? JSONEncoder().encode(migrated) {
            defaults.set(data, forKey: ruleKey)
            defaults.removeObject(forKey: legacyDateKey)
        }
        return migrated
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
                visibleCards: [.today, .sevenDays, .total, .planProgress, .resetCredits, .subscriptionExpiry]
            )
        case .glm:
            ProviderPreferences(
                ringPrimaryHex: "#14B8A6",
                ringSecondaryHex: "#F97316",
                cardAccentHex: "#10B981",
                visibleCards: [.tokenUsage, .weeklyQuota, .mcpUsage, .multiplier, .subscriptionExpiry]
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
            return migrateSubscriptionExpiry(migrated, provider: provider, defaults: defaults)
        }
        return migrateSubscriptionExpiry(decoded, provider: provider, defaults: defaults)
    }

    private static func migrateSubscriptionExpiry(_ preferences: ProviderPreferences, provider: ProviderID, defaults: UserDefaults) -> ProviderPreferences {
        let key = Keys.subscriptionExpiryMigrated(provider)
        guard !defaults.bool(forKey: key) else {
            return preferences
        }
        var migrated = preferences
        migrated.visibleCards.insert(.subscriptionExpiry)
        migrated.save(provider: provider, defaults: defaults)
        defaults.set(true, forKey: key)
        return migrated
    }

    func save(provider: ProviderID, defaults: UserDefaults) {
        guard let data = try? JSONEncoder().encode(self) else { return }
        defaults.set(data, forKey: Keys.provider(provider))
    }
}

private enum Keys {
    static let refreshIntervalMinutes = "refreshIntervalMinutes"
    static let layoutPreset = "layoutPreset"
    static let providerLayoutMode = "providerLayoutMode"
    static let codexQuotaRingMode = "codexQuotaRingMode"
    static let glmAuthToken = "glmAuthToken"
    static let glmBaseURL = "glmBaseURL"
    static let codexManualSubscriptionRule = "subscriptionExpiry.codex.manualRule"
    static let codexRemoteSubscriptionLookupEnabled = "subscriptionExpiry.codex.remoteLookupEnabled"
    static let glmManualSubscriptionRule = "subscriptionExpiry.glm.manualRule"
    static let codexManualSubscriptionExpiry = "subscriptionExpiry.codex.manual"
    static let glmManualSubscriptionExpiry = "subscriptionExpiry.glm.manual"
    static let codexResetCreditsMigrated = "providerPreferences.codex.resetCreditsMigrated"

    static func provider(_ provider: ProviderID) -> String {
        "providerPreferences.\(provider.rawValue)"
    }

    static func subscriptionExpiryMigrated(_ provider: ProviderID) -> String {
        "providerPreferences.\(provider.rawValue).subscriptionExpiryMigrated"
    }
}
