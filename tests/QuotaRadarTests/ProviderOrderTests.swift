import XCTest
@testable import QuotaRadar

final class ProviderOrderTests: XCTestCase {
    private func defaults() -> UserDefaults {
        let suite = "ProviderOrderTests.\(UUID())"
        let defaults = UserDefaults(suiteName: suite)!
        addTeardownBlock { UserDefaults(suiteName: suite)?.removePersistentDomain(forName: suite) }
        return defaults
    }

    func testOrderDefaultsMovesAndPersistsWithoutDuplicates() {
        let defaults = defaults()
        let settings = AppSettings(defaults: defaults)
        XCTAssertEqual(settings.providerOrder, [.codex, .glm, .claude])
        settings.moveProvider(.claude, by: -1)
        settings.moveProvider(.claude, by: -1)
        settings.moveProvider(.claude, by: -1)
        settings.moveProvider(.glm, by: 1)
        XCTAssertEqual(settings.providerOrder, [.claude, .codex, .glm])
        XCTAssertEqual(AppSettings(defaults: defaults).providerOrder, settings.providerOrder)
    }

    func testHiddenProviderRetainsPositionAcrossLayouts() {
        let settings = AppSettings(defaults: defaults())
        settings.moveProvider(.claude, by: -1)
        settings.setProviderVisible(false, provider: .claude)
        for mode in ProviderLayoutMode.allCases {
            settings.providerLayoutMode = mode
            XCTAssertEqual(settings.orderedVisibleProviders, [.codex, .glm])
            XCTAssertEqual(settings.providerOrder, [.codex, .claude, .glm])
        }
        settings.setProviderVisible(true, provider: .claude)
        XCTAssertEqual(settings.orderedVisibleProviders, [.codex, .claude, .glm])
    }

    func testOldOrDamagedOrderPreservesKnownItemsAndAppendsMissingProviders() {
        let defaults = defaults()
        defaults.set(["glm", "unknown", "glm", "codex"], forKey: "providerOrder")
        XCTAssertEqual(AppSettings(defaults: defaults).providerOrder, [.glm, .codex, .claude])
    }
}
