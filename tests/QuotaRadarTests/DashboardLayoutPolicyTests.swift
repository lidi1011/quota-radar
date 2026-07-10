import CoreGraphics
import XCTest
@testable import QuotaRadar

final class DashboardLayoutPolicyTests: XCTestCase {
    func testRingOnlyPanelWidthsMatchAllPresets() {
        XCTAssertEqual(LayoutPreset.compact.ringOnlyPanelWidth, 320)
        XCTAssertEqual(LayoutPreset.standard.ringOnlyPanelWidth, 390)
        XCTAssertEqual(LayoutPreset.spacious.ringOnlyPanelWidth, 458)
    }

    func testHorizontalSingleProviderUsesAvailableWidth() {
        let policy = DashboardLayoutPolicy(
            preset: .standard,
            providerLayoutMode: .horizontal,
            providers: [.init(provider: .codex, hasRenderedCards: true)]
        )

        XCTAssertEqual(policy.panelWidth(for: .codex, viewportWidth: 900), 856)
    }

    func testSpaciousVerticalCardsEnableHorizontalReachabilityInNarrowWindow() {
        let policy = DashboardLayoutPolicy(
            preset: .spacious,
            providerLayoutMode: .vertical,
            providers: [.init(provider: .codex, hasRenderedCards: true)]
        )

        XCTAssertEqual(policy.scrollAxes(viewportWidth: 352), .both)
        XCTAssertEqual(policy.minimumContentWidth, 424)
    }
}
