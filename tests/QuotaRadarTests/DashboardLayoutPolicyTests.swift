import CoreGraphics
import XCTest
@testable import QuotaRadar

final class DashboardLayoutPolicyTests: XCTestCase {
    func testHorizontalRingRowUsesMeasuredHeightInsteadOfEstimatedMinimum() {
        for preset in LayoutPreset.allCases {
            let policy = DashboardLayoutPolicy(
                preset: preset, providerLayoutMode: .horizontal,
                providers: [.init(provider: .codex, hasRenderedCards: false),
                            .init(provider: .glm, hasRenderedCards: false),
                            .init(provider: .claude, hasRenderedCards: false)]
            )
            let measuredHeight = policy.minimumContentHeight - 34.25

            XCTAssertEqual(policy.minimumContentHeight(measuredContentHeight: measuredHeight), ceil(measuredHeight))
            XCTAssertEqual(policy.minimumContentHeight(measuredContentHeight: 0), policy.minimumContentHeight)
        }
    }

    func testMeasuredFullStackHeightDoesNotRaiseVerticalOrCardLayoutMinimum() {
        var policy = DashboardLayoutPolicy(
            preset: .compact, providerLayoutMode: .vertical,
            providers: [.init(provider: .codex, hasRenderedCards: false),
                        .init(provider: .glm, hasRenderedCards: false)]
        )
        XCTAssertEqual(policy.minimumContentHeight(measuredContentHeight: 1000), policy.minimumContentHeight)
        policy.providerLayoutMode = .horizontal
        policy.providers[0].hasRenderedCards = true
        XCTAssertEqual(policy.minimumContentHeight(measuredContentHeight: 1000), policy.minimumContentHeight)
        policy.providers = []
        XCTAssertEqual(policy.minimumContentHeight(measuredContentHeight: 100), policy.minimumContentHeight)
    }

    func testLayoutTransitionRejectsStaleHeightAndFitsAfterNewMeasurement() {
        let vertical = DashboardLayoutPolicy(
            preset: .compact, providerLayoutMode: .vertical,
            providers: [.init(provider: .codex, hasRenderedCards: false),
                        .init(provider: .glm, hasRenderedCards: false),
                        .init(provider: .claude, hasRenderedCards: false)]
        )
        var horizontal = vertical
        horizontal.providerLayoutMode = .horizontal
        let oldMeasurement = DashboardContentMeasurement(layout: vertical, height: 960)
        XCTAssertEqual(oldMeasurement.height(for: vertical), 960)
        XCTAssertEqual(oldMeasurement.height(for: horizontal), 0)

        var state = WindowAutoFitState()
        var input = WindowAutoFitState.Input(
            layout: vertical, visibleFrame: CGRect(x: 0, y: 0, width: 1440, height: 900),
            layoutInsets: CGSize(width: 0, height: 38), hasMeasuredContent: true
        )
        XCTAssertTrue(state.shouldFit(input, isLiveResizing: false))
        input.layout = horizontal
        input.hasMeasuredContent = oldMeasurement.height(for: horizontal) > 0
        XCTAssertTrue(state.shouldFit(input, isLiveResizing: false))
        let newMeasurement = DashboardContentMeasurement(layout: horizontal, height: 331)
        input.hasMeasuredContent = newMeasurement.height(for: horizontal) > 0
        XCTAssertTrue(state.shouldFit(input, isLiveResizing: false))
        XCTAssertFalse(state.shouldFit(input, isLiveResizing: false))
        horizontal.preset = .standard
        XCTAssertEqual(newMeasurement.height(for: horizontal), 0)
    }

    func testAutoFitPreservesManualSizeUntilLayoutOrScreenChanges() {
        var state = WindowAutoFitState()
        var input = WindowAutoFitState.Input(
            layout: DashboardLayoutPolicy(preset: .compact, providerLayoutMode: .vertical,
                providers: [.init(provider: .codex, hasRenderedCards: false),
                            .init(provider: .glm, hasRenderedCards: false),
                            .init(provider: .claude, hasRenderedCards: false)]),
            visibleFrame: CGRect(x: 0, y: 0, width: 1440, height: 900),
            layoutInsets: CGSize(width: 0, height: 38), hasMeasuredContent: true)
        XCTAssertTrue(state.shouldFit(input, isLiveResizing: false))
        XCTAssertFalse(state.shouldFit(input, isLiveResizing: true))
        XCTAssertFalse(state.shouldFit(input, isLiveResizing: false))
        input.layout.preset = .standard
        XCTAssertFalse(state.shouldFit(input, isLiveResizing: true))
        XCTAssertTrue(state.shouldFit(input, isLiveResizing: false))
        input.visibleFrame.size.height = 1080
        XCTAssertTrue(state.shouldFit(input, isLiveResizing: false))
        XCTAssertFalse(state.shouldFit(input, isLiveResizing: false))
    }

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

    func testContentLayoutHeightIncludesToolbarInsetInWindowFrame() {
        let size = WindowFramePolicy.frameSize(
            contentLayoutSize: CGSize(width: 434, height: 834),
            layoutInsets: CGSize(width: 0, height: 52),
            visibleFrame: CGRect(x: 0, y: 76, width: 1920, height: 974)
        )

        XCTAssertEqual(size, CGSize(width: 434, height: 886))
    }

    func testContentLayoutHeightClampsAfterAddingToolbarInset() {
        let size = WindowFramePolicy.frameSize(
            contentLayoutSize: CGSize(width: 514, height: 988),
            layoutInsets: CGSize(width: 0, height: 52),
            visibleFrame: CGRect(x: 0, y: 76, width: 1920, height: 974)
        )

        XCTAssertEqual(size, CGSize(width: 514, height: 974))
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
        XCTAssertEqual(policy.ringOnlyContentHeight, 676)
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
        XCTAssertEqual(policy.ringOnlyContentHeight, 988)
    }

    func testHorizontalRingOnlyLayoutUsesSinglePanelHeight() {
        let policy = DashboardLayoutPolicy(
            preset: .standard,
            providerLayoutMode: .horizontal,
            providers: [
                .init(provider: .codex, hasRenderedCards: false),
                .init(provider: .glm, hasRenderedCards: false)
            ]
        )

        XCTAssertEqual(policy.ringOnlyContentHeight, 426)
    }

    func testRenderedCardsDoNotUseRingOnlyContentHeight() {
        let policy = DashboardLayoutPolicy(
            preset: .standard,
            providerLayoutMode: .vertical,
            providers: [.init(provider: .codex, hasRenderedCards: true)]
        )

        XCTAssertNil(policy.ringOnlyContentHeight)
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
        XCTAssertEqual(policy.minimumBodyWidth, 276)
        XCTAssertEqual(policy.minimumBodyHeight, 390)
    }
}
