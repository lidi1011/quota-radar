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

    func testExpandedWindowMovesLeftToRemainVisible() {
        let frame = WindowFramePolicy.clampedFrame(
            currentFrame: CGRect(x: 1568, y: 30, width: 352, height: 709),
            targetSize: CGSize(width: 996, height: 657),
            visibleFrame: CGRect(x: 0, y: 0, width: 1920, height: 1080)
        )

        XCTAssertEqual(frame.maxX, 1920)
        XCTAssertEqual(frame.minX, 924)
    }

    func testHorizontalRingOnlyLayoutFitsHeight() {
        let policy = DashboardLayoutPolicy(
            preset: .standard,
            providerLayoutMode: .horizontal,
            providers: [
                .init(provider: .codex, hasRenderedCards: false),
                .init(provider: .glm, hasRenderedCards: false)
            ]
        )

        XCTAssertTrue(policy.fitsHeight)
        XCTAssertEqual(policy.minimumContentHeight, 426)
    }

    func testVerticalRingOnlyLayoutAlsoFitsHeightDeterministically() {
        let policy = DashboardLayoutPolicy(
            preset: .compact,
            providerLayoutMode: .vertical,
            providers: [
                .init(provider: .codex, hasRenderedCards: false),
                .init(provider: .glm, hasRenderedCards: false)
            ]
        )

        XCTAssertTrue(policy.fitsHeight)
    }

    func testVerticalSpaciousLayoutRequiresCompleteFirstPanelHeight() {
        let policy = DashboardLayoutPolicy(
            preset: .spacious,
            providerLayoutMode: .vertical,
            providers: [
                .init(provider: .codex, hasRenderedCards: false),
                .init(provider: .glm, hasRenderedCards: false)
            ]
        )

        XCTAssertEqual(policy.minimumContentHeight, 506)
    }

    func testSelectedButUnavailableCardDoesNotCountAsRendered() {
        let preferences = ProviderPreferences(
            ringPrimaryHex: "#1E88FF",
            ringSecondaryHex: "#8B5CF6",
            cardAccentHex: "#2563EB",
            visibleCards: [.subscriptionExpiry]
        )

        XCTAssertFalse(
            ProviderPanelView.hasRenderedCards(
                snapshot: nil,
                preferences: preferences
            )
        )
    }

    func testAvailableSelectedCardCountsAsRendered() {
        let snapshot = ProviderSnapshot(
            provider: .codex,
            generatedAt: Date(timeIntervalSince1970: 0),
            windows: [],
            cards: [
                UsageCard(
                    id: .today,
                    title: "今日",
                    systemImage: "sun.max.fill",
                    primaryValue: "1M",
                    trailingValue: "",
                    breakdown: nil,
                    note: nil
                )
            ],
            progress: nil,
            statusMessage: ""
        )
        let preferences = ProviderPreferences(
            ringPrimaryHex: "#1E88FF",
            ringSecondaryHex: "#8B5CF6",
            cardAccentHex: "#2563EB",
            visibleCards: [.today]
        )

        XCTAssertTrue(
            ProviderPanelView.hasRenderedCards(
                snapshot: snapshot,
                preferences: preferences
            )
        )
    }

    func testAllPrimaryLayoutCombinationsKeepOverflowReachable() {
        for preset in LayoutPreset.allCases {
            for providerLayoutMode in ProviderLayoutMode.allCases {
                for hasRenderedCards in [false, true] {
                    let policy = DashboardLayoutPolicy(
                        preset: preset,
                        providerLayoutMode: providerLayoutMode,
                        providers: [
                            .init(provider: .codex, hasRenderedCards: hasRenderedCards),
                            .init(provider: .glm, hasRenderedCards: hasRenderedCards)
                        ]
                    )

                    XCTAssertGreaterThanOrEqual(policy.minimumContentWidth, 320)
                    XCTAssertGreaterThanOrEqual(policy.minimumContentHeight, 360)
                    if policy.scrollAxes(viewportWidth: 352) == .vertical {
                        XCTAssertLessThanOrEqual(policy.minimumContentWidth, 353)
                    }
                }
            }
        }
    }

    func testMixedHorizontalLayoutUsesBothAxesInNarrowViewport() {
        let policy = DashboardLayoutPolicy(
            preset: .spacious,
            providerLayoutMode: .horizontal,
            providers: [
                .init(provider: .codex, hasRenderedCards: true),
                .init(provider: .glm, hasRenderedCards: false)
            ]
        )

        XCTAssertEqual(policy.scrollAxes(viewportWidth: 514), .both)
        XCTAssertEqual(policy.minimumContentWidth, 906)
    }

    func testNoProvidersReportsEmptyState() {
        let policy = DashboardLayoutPolicy(
            preset: .standard,
            providerLayoutMode: .vertical,
            providers: []
        )

        XCTAssertTrue(policy.isEmpty)
        XCTAssertEqual(policy.minimumContentWidth, 320)
        XCTAssertEqual(policy.minimumContentHeight, 426)
    }
}
