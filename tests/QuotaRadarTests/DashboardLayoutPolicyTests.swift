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
}
