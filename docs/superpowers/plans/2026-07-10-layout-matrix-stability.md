# Layout Matrix Stability Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make every Quota Radar provider/card/orientation/density combination reachable, stable, and screen-bounded without changing quota data behavior.

**Architecture:** Add a pure `DashboardLayoutPolicy` that owns layout metrics and a pure `WindowFramePolicy` that clamps resized windows to the active screen. `ContentView` consumes those policies, while `ProviderPanelView` independently adapts its internal ring/card layout from available width.

**Tech Stack:** Swift 6, SwiftUI, AppKit `NSWindow`, XCTest, Swift Package Manager, macOS 14+

## Global Constraints

- Keep the default settings: standard density, vertical Provider arrangement, both Providers visible.
- Do not change provider data sources, parsers, refresh behavior, colors, or card information hierarchy.
- Do not introduce APIs requiring macOS 15 or later.
- Do not add `.planning/`, `.codex/`, generated DMGs, credentials, tokens, cookies, certificates, or signing material to Git.
- Follow `DESIGN.md`; generated visual QA artifacts belong under `artifacts/product-design/`.
- Every production behavior begins with a failing test and a verified RED result.

---

### Task 1: Pure dashboard layout metrics

**Files:**
- Create: `Sources/QuotaRadar/Models/DashboardLayoutPolicy.swift`
- Modify: `Sources/QuotaRadar/Models/LayoutPreset.swift`
- Create: `Tests/QuotaRadarTests/DashboardLayoutPolicyTests.swift`

**Interfaces:**
- Consumes: `LayoutPreset`, `ProviderLayoutMode`, `ProviderID`.
- Produces: `ProviderLayoutContent`, `DashboardLayoutPolicy`, `DashboardScrollAxes`, and preset metrics `ringOnlyPanelWidth`, `cardPanelMinimumWidth`, `cardPanelPreferredWidth`.

- [ ] **Step 1: Write failing preset and provider-count tests**

```swift
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
```

- [ ] **Step 2: Run the focused tests and verify RED**

Run: `swift test --filter DashboardLayoutPolicyTests`

Expected: compilation fails because `DashboardLayoutPolicy`, `ProviderLayoutContent`, and the new preset metrics do not exist.

- [ ] **Step 3: Implement the minimal metrics and policy**

```swift
import CoreGraphics

struct ProviderLayoutContent: Equatable {
    var provider: ProviderID
    var hasRenderedCards: Bool
}

enum DashboardScrollAxes: Equatable {
    case vertical
    case both
}

struct DashboardLayoutPolicy {
    var preset: LayoutPreset
    var providerLayoutMode: ProviderLayoutMode
    var providers: [ProviderLayoutContent]

    var minimumStackWidth: CGFloat {
        let widths = providers.map { $0.hasRenderedCards ? preset.cardPanelMinimumWidth : preset.ringOnlyPanelWidth }
        switch providerLayoutMode {
        case .vertical:
            return widths.max() ?? 0
        case .horizontal:
            return widths.reduce(0, +) + CGFloat(max(0, widths.count - 1)) * preset.contentSpacing
        }
    }

    var minimumContentWidth: CGFloat {
        max(320, minimumStackWidth + preset.contentHorizontalPadding * 2)
    }

    func scrollAxes(viewportWidth: CGFloat) -> DashboardScrollAxes {
        minimumContentWidth > viewportWidth + 1 ? .both : .vertical
    }

    func panelWidth(for provider: ProviderID, viewportWidth: CGFloat) -> CGFloat? {
        guard providerLayoutMode == .horizontal,
              let content = providers.first(where: { $0.provider == provider }) else { return nil }
        let count = max(1, providers.count)
        let available = viewportWidth - preset.contentHorizontalPadding * 2
            - CGFloat(max(0, count - 1)) * preset.contentSpacing
        let share = max(0, available / CGFloat(count))
        let minimum = content.hasRenderedCards ? preset.cardPanelMinimumWidth : preset.ringOnlyPanelWidth
        return max(share, minimum)
    }
}
```

Add these exact `LayoutPreset` properties:

```swift
var ringOnlyPanelWidth: CGFloat {
    panelPadding * 2 + ringOnlyHeaderHeight + panelSpacing + ringSize + 12 + ringOnlyLegendHeight
}

var cardPanelMinimumWidth: CGFloat {
    max(ringColumnWidth, cardMinWidth) + panelPadding * 2
}

var cardPanelPreferredWidth: CGFloat {
    cardMinWidth * 2 + cardSpacing + panelPadding * 2
}

private var ringOnlyHeaderHeight: CGFloat {
    switch self { case .compact: 42; case .standard: 50; case .spacious: 58 }
}

private var ringOnlyLegendHeight: CGFloat { ringOnlyHeaderHeight }
```

- [ ] **Step 4: Run the focused tests and verify GREEN**

Run: `swift test --filter DashboardLayoutPolicyTests`

Expected: all Task 1 tests pass.

- [ ] **Step 5: Commit Task 1**

```bash
git add Sources/QuotaRadar/Models/DashboardLayoutPolicy.swift Sources/QuotaRadar/Models/LayoutPreset.swift Tests/QuotaRadarTests/DashboardLayoutPolicyTests.swift
git commit -m "Add testable dashboard layout policy"
```

---

### Task 2: Screen-bounded window sizing and deterministic viewport height

**Files:**
- Modify: `Sources/QuotaRadar/Models/DashboardLayoutPolicy.swift`
- Modify: `Sources/QuotaRadar/Views/ContentView.swift`
- Modify: `Tests/QuotaRadarTests/DashboardLayoutPolicyTests.swift`

**Interfaces:**
- Consumes: Task 1 `DashboardLayoutPolicy`.
- Produces: `WindowFramePolicy.clampedFrame(currentFrame:targetSize:visibleFrame:)`, `minimumContentHeight`, `fitsWidth`, and `fitsHeight`.

- [ ] **Step 1: Write failing window and height tests**

```swift
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
```

- [ ] **Step 2: Run focused tests and verify RED**

Run: `swift test --filter DashboardLayoutPolicyTests`

Expected: fails because `WindowFramePolicy`, `fitsHeight`, and `minimumContentHeight` are missing.

- [ ] **Step 3: Implement pure frame clamping and height rules**

```swift
enum WindowFramePolicy {
    static func clampedFrame(currentFrame: CGRect, targetSize: CGSize, visibleFrame: CGRect) -> CGRect {
        let size = CGSize(
            width: min(targetSize.width, visibleFrame.width),
            height: min(targetSize.height, visibleFrame.height)
        )
        let x = min(max(currentFrame.minX, visibleFrame.minX), visibleFrame.maxX - size.width)
        let proposedY = currentFrame.maxY - size.height
        let y = min(max(proposedY, visibleFrame.minY), visibleFrame.maxY - size.height)
        return CGRect(origin: CGPoint(x: x, y: y), size: size)
    }
}
```

Add policy rules:

```swift
var minimumContentHeight: CGFloat {
    max(360, preset.ringOnlyPanelWidth + preset.contentVerticalPadding * 2)
}

var fitsWidth: Bool {
    !providers.isEmpty && providers.allSatisfy { !$0.hasRenderedCards }
}

var fitsHeight: Bool {
    providers.count == 1 || (providerLayoutMode == .horizontal && providers.allSatisfy { !$0.hasRenderedCards })
}
```

- [ ] **Step 4: Replace the fixed window fitter inputs in `ContentView`**

Create the policy from actual provider contents, pass `minimumContentWidth`, `minimumContentHeight`, `fitsWidth`, and `fitsHeight` to `MainWindowSizeFitter`, and replace the fixed `minimumContentSize` constant with those dynamic values. Clamp the final `NSWindow` frame with `WindowFramePolicy` and `window.screen?.visibleFrame` before calling `setFrame`.

- [ ] **Step 5: Run focused and full tests**

Run: `swift test --filter DashboardLayoutPolicyTests && swift test`

Expected: all tests pass; the existing 42 tests remain green.

- [ ] **Step 6: Commit Task 2**

```bash
git add Sources/QuotaRadar/Models/DashboardLayoutPolicy.swift Sources/QuotaRadar/Views/ContentView.swift Tests/QuotaRadarTests/DashboardLayoutPolicyTests.swift
git commit -m "Keep dashboard windows within visible screen"
```

---

### Task 3: Rendered-card truth and independent panel responsiveness

**Files:**
- Modify: `Sources/QuotaRadar/Views/ProviderPanelView.swift`
- Modify: `Sources/QuotaRadar/Views/ContentView.swift`
- Modify: `Tests/QuotaRadarTests/DashboardLayoutPolicyTests.swift`

**Interfaces:**
- Consumes: Task 1 `ProviderLayoutContent` and `DashboardLayoutPolicy`.
- Produces: `ProviderPanelView.hasRenderedCards(snapshot:preferences:)` and panel layout independent of `ProviderLayoutMode`.

- [ ] **Step 1: Write failing rendered-card tests**

```swift
func testSelectedButUnavailableCardDoesNotCountAsRendered() {
    let preferences = ProviderPreferences(
        ringPrimaryHex: "#1E88FF",
        ringSecondaryHex: "#8B5CF6",
        cardAccentHex: "#2563EB",
        visibleCards: [.subscriptionExpiry]
    )
    XCTAssertFalse(ProviderPanelView.hasRenderedCards(snapshot: nil, preferences: preferences))
}

func testAvailableSelectedCardCountsAsRendered() {
    let snapshot = ProviderSnapshot.fixture(cards: [UsageCard.fixture(id: .today)])
    let preferences = ProviderPreferences(
        ringPrimaryHex: "#1E88FF",
        ringSecondaryHex: "#8B5CF6",
        cardAccentHex: "#2563EB",
        visibleCards: [.today]
    )
    XCTAssertTrue(ProviderPanelView.hasRenderedCards(snapshot: snapshot, preferences: preferences))
}
```

Use small test-only fixtures in the test file with the existing `ProviderSnapshot` and `UsageCard` initializers; do not add fixture APIs to production.

- [ ] **Step 2: Run the focused tests and verify RED**

Run: `swift test --filter DashboardLayoutPolicyTests`

Expected: fails because the static rendered-card query does not exist.

- [ ] **Step 3: Expose rendered-card truth from `ProviderPanelView`**

Extract the existing `gridCards` composition into a static helper that applies the same selected-card, progress, reset-credit, and subscription ordering. Use the helper for both rendering and `ContentView` policy inputs.

- [ ] **Step 4: Remove `providerLayoutMode` from `ProviderPanelView`**

Replace the conditional branch with one independent responsive layout:

```swift
if gridCards.isEmpty {
    centeredRingBlock
} else {
    ViewThatFits(in: .horizontal) {
        HStack(alignment: .center, spacing: layout.horizontalBlockSpacing) {
            ringBlock.frame(width: layout.ringColumnWidth)
            dashboardBlock
        }
        VStack(alignment: .leading, spacing: layout.panelSpacing) {
            centeredRingBlock
            dashboardBlock
        }
    }
}
```

- [ ] **Step 5: Integrate dynamic scroll width in `ContentView`**

Build `[ProviderLayoutContent]` from actual rendered-card truth. Apply `.frame(minWidth: policy.minimumStackWidth)` to the provider stack and choose `[.vertical]` or `[.vertical, .horizontal]` from `policy.scrollAxes(viewportWidth:)` so spacious vertical content is reachable instead of clipped.

- [ ] **Step 6: Run all tests and commit**

Run: `swift test`

Expected: all tests pass.

```bash
git add Sources/QuotaRadar/Views/ProviderPanelView.swift Sources/QuotaRadar/Views/ContentView.swift Tests/QuotaRadarTests/DashboardLayoutPolicyTests.swift
git commit -m "Decouple provider and panel layouts"
```

---

### Task 4: Empty state and matrix regression coverage

**Files:**
- Modify: `Sources/QuotaRadar/Views/ContentView.swift`
- Modify: `Tests/QuotaRadarTests/DashboardLayoutPolicyTests.swift`
- Modify: `DESIGN.md`

**Interfaces:**
- Consumes: completed layout policies.
- Produces: explicit zero-provider empty state and exhaustive layout regression tests.

- [ ] **Step 1: Add failing matrix tests**

Use nested loops over all `LayoutPreset.allCases`, `ProviderLayoutMode.allCases`, and `[false, true]` rendered-card states. Assert that:

```swift
XCTAssertGreaterThanOrEqual(policy.minimumContentWidth, 320)
XCTAssertGreaterThanOrEqual(policy.minimumContentHeight, 360)
if policy.scrollAxes(viewportWidth: 352) == .vertical {
    XCTAssertLessThanOrEqual(policy.minimumContentWidth, 353)
}
```

Add explicit mixed-state, zero-provider, and single-provider assertions.

- [ ] **Step 2: Run focused tests and verify RED**

Run: `swift test --filter DashboardLayoutPolicyTests`

Expected: zero-provider assertions fail until the policy and empty state contract are implemented.

- [ ] **Step 3: Add the empty state**

When `visibleProviders.isEmpty`, render:

```swift
ContentUnavailableView {
    Label("未显示 Provider", systemImage: "gauge.with.dots.needle.0percent")
} description: {
    Text("请在设置中启用 Codex 或 GLM。")
} actions: {
    SettingsLink { Text("打开设置") }
}
```

Keep toolbar refresh/settings controls unchanged.

- [ ] **Step 4: Document the layout contract**

Update `DESIGN.md` so Provider arrangement controls only the outer stack, panel content reflows independently, and window sizing is screen-bounded with scroll fallback.

- [ ] **Step 5: Run all tests and commit**

Run: `swift test`

Expected: matrix tests and all existing tests pass.

```bash
git add Sources/QuotaRadar/Views/ContentView.swift Tests/QuotaRadarTests/DashboardLayoutPolicyTests.swift DESIGN.md
git commit -m "Cover dashboard layout matrix"
```

---

### Task 5: Real-app verification and handoff

**Files:**
- Modify: `.planning/HANDOFF.md`
- Modify: `.planning/TODO.md`
- Modify: `.planning/USER_REQUIRED.md` only if a human-only blocker is discovered.
- Create/Update: `artifacts/product-design/ui-audit-2026-07-10/` screenshots.

**Interfaces:**
- Consumes: completed implementation.
- Produces: verified `.app` behavior and durable handoff state.

- [ ] **Step 1: Build and launch the app bundle**

Run: `./script/build_and_run.sh --verify`

Expected: build succeeds and the Quota Radar process remains running.

- [ ] **Step 2: Verify the five required UI sequences**

Check in the live app:

1. compact/vertical/ring-only → spacious;
2. narrow cards → horizontal;
3. horizontal ring-only through all three presets;
4. mixed Codex-card/GLM-ring-only;
5. one Provider and zero Providers.

For each sequence confirm no inaccessible clipping, no off-screen window, no unexplained bottom whitespace, and a complete first panel.

- [ ] **Step 3: Re-run the full suite and inspect the diff**

Run: `swift test`

Run: `git diff --check && git status --short`

Expected: all tests pass; only intended source, test, design, planning, and audit-artifact changes are present.

- [ ] **Step 4: Update handoff documents**

Record the layout matrix fix, exact verified commands, remaining risks, and next action in `.planning/HANDOFF.md` and `.planning/TODO.md`.

- [ ] **Step 5: Commit implementation handoff**

```bash
git add Sources Tests DESIGN.md
git commit -m "Stabilize dashboard layout combinations"
```

`.planning/HANDOFF.md` and `.planning/TODO.md` remain local-only and must not be added to the public repository.
