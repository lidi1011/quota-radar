import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var settings: AppSettings
    @EnvironmentObject private var store: UsageStore
    @State private var contentMeasurement: DashboardContentMeasurement?

    private var visibleProviders: [ProviderID] {
        settings.orderedVisibleProviders
    }

    private var providerLayoutContents: [ProviderLayoutContent] {
        visibleProviders.map { provider in
            let preferences = settings.preferences(for: provider)
            return ProviderLayoutContent(
                provider: provider,
                hasRenderedCards: ProviderPanelView.hasRenderedCards(
                    snapshot: store.snapshots[provider],
                    preferences: preferences
                )
            )
        }
    }

    private var layoutPolicy: DashboardLayoutPolicy {
        DashboardLayoutPolicy(
            preset: settings.layoutPreset,
            providerLayoutMode: settings.providerLayoutMode,
            providers: providerLayoutContents
        )
    }

    var body: some View {
        GeometryReader { windowProxy in
            let policy = layoutPolicy
            let contentHeight = contentMeasurement?.height(for: policy) ?? 0
            ScrollView(scrollAxes(policy: policy, viewportWidth: windowProxy.size.width)) {
                Group {
                    if policy.isEmpty {
                        emptyProviderView
                            .frame(
                                minWidth: policy.minimumBodyWidth,
                                minHeight: policy.minimumBodyHeight
                            )
                    } else {
                        providerStack(containerWidth: windowProxy.size.width, policy: policy)
                            .frame(minWidth: policy.minimumStackWidth)
                    }
                }
                .padding(.horizontal, settings.layoutPreset.contentHorizontalPadding)
                .padding(.vertical, settings.layoutPreset.contentVerticalPadding)
                .background(
                    GeometryReader { proxy in
                        Color.clear.preference(
                            key: ContentHeightPreferenceKey.self,
                            value: DashboardContentMeasurement(layout: policy, height: proxy.size.height)
                        )
                    }
                )
            }
            .scrollIndicators(.visible)
            .onPreferenceChange(ContentHeightPreferenceKey.self) { measurement in
                contentMeasurement = measurement
            }
            .background(
                MainWindowSizeFitter(
                    layout: policy,
                    hasMeasuredContent: contentHeight > 0,
                    contentWidth: policy.fitsWidth ? policy.minimumContentWidth : nil,
                    contentHeight: contentHeight > 0 ? contentHeight : (policy.ringOnlyContentHeight ?? 0),
                    minimumContentWidth: policy.minimumContentWidth,
                    minimumContentHeight: policy.minimumContentHeight(measuredContentHeight: contentHeight),
                    shouldFitWidth: policy.fitsWidth,
                    shouldFitHeight: policy.fitsHeight
                )
            )
            .background(
                LinearGradient(
                    colors: [
                        Color(nsColor: .windowBackgroundColor),
                        Color(hex: "#172033").opacity(0.28),
                        Color(hex: "#4A1D2E").opacity(0.22)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .toolbar {
                ToolbarItemGroup {
                    Button {
                        Task { await store.refreshAll(force: true) }
                    } label: {
                        Label("刷新", systemImage: "arrow.clockwise")
                    }
                    SettingsLink {
                        Label("设置", systemImage: "gearshape")
                    }
                }
            }
        }
        .frame(minWidth: 320, minHeight: min(360, layoutPolicy.minimumContentHeight(
            measuredContentHeight: contentMeasurement?.height(for: layoutPolicy) ?? 0
        )))
    }

    private func scrollAxes(policy: DashboardLayoutPolicy, viewportWidth: CGFloat) -> Axis.Set {
        switch policy.scrollAxes(viewportWidth: viewportWidth) {
        case .vertical:
            [.vertical]
        case .both:
            [.vertical, .horizontal]
        }
    }

    private var emptyProviderView: some View {
        ContentUnavailableView {
            Label("未显示 Provider", systemImage: "rectangle.stack.badge.plus")
        } description: {
            Text("请在设置中启用 Codex、GLM 或 Claude Code。")
        } actions: {
            SettingsLink {
                Text("打开设置")
            }
        }
    }

    @ViewBuilder
    private func providerStack(containerWidth: CGFloat, policy: DashboardLayoutPolicy) -> some View {
        switch settings.providerLayoutMode {
        case .vertical:
            VStack(alignment: .leading, spacing: settings.layoutPreset.contentSpacing) {
                providerPanels(containerWidth: containerWidth, policy: policy)
            }
        case .horizontal:
            HStack(alignment: .top, spacing: settings.layoutPreset.contentSpacing) {
                providerPanels(containerWidth: containerWidth, policy: policy)
            }
        }
    }

    private func providerPanels(containerWidth: CGFloat, policy: DashboardLayoutPolicy) -> some View {
        ForEach(visibleProviders) { provider in
            ProviderPanelView(
                provider: provider,
                snapshot: store.snapshots[provider],
                displayedWindows: displayedWindows(for: provider),
                state: store.states[provider] ?? .idle,
                preferences: settings.preferences(for: provider),
                layout: settings.layoutPreset,
                refreshEnabled: provider != .claude || settings.claudeReadingEnabled
            ) {
                Task { await store.refresh(provider) }
            }
            .frame(width: policy.panelWidth(for: provider, viewportWidth: containerWidth))
        }
    }

    private func displayedWindows(for provider: ProviderID) -> [UsageWindow] {
        let windows = store.snapshots[provider]?.windows ?? placeholderWindows(for: provider)
        switch provider {
        case .codex:
            return settings.codexQuotaRingMode.windows(from: windows)
        case .glm, .claude:
            return windows
        }
    }

    private func placeholderWindows(for provider: ProviderID) -> [UsageWindow] {
        switch provider {
        case .claude:
            ClaudeCodeProvider.unavailable("").windows
        case .codex:
            [
                .placeholder(id: "5h", label: "5 小时"),
                .placeholder(id: "7d", label: "7 天")
            ]
        case .glm:
            [
                .placeholder(id: "token", label: "5 小时"),
                .placeholder(id: "weekly", label: "7 天")
            ]
        }
    }

}

private struct ContentHeightPreferenceKey: PreferenceKey {
    static var defaultValue: DashboardContentMeasurement? { nil }

    static func reduce(value: inout DashboardContentMeasurement?, nextValue: () -> DashboardContentMeasurement?) {
        if let next = nextValue() {
            value = next
        }
    }
}

private struct MainWindowSizeFitter: NSViewRepresentable {
    var layout: DashboardLayoutPolicy
    var hasMeasuredContent: Bool
    var contentWidth: CGFloat?
    var contentHeight: CGFloat
    var minimumContentWidth: CGFloat
    var minimumContentHeight: CGFloat
    var shouldFitWidth: Bool
    var shouldFitHeight: Bool

    final class Coordinator {
        var autoFit = WindowAutoFitState()
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> NSView {
        NSView()
    }

    func updateNSView(_ view: NSView, context: Context) {
        DispatchQueue.main.async {
            guard let window = view.window else { return }
            let currentContentWidth = window.contentLayoutRect.width
            let currentContentHeight = window.contentLayoutRect.height
            let visibleFrame = window.screen?.visibleFrame ?? window.frame
            let layoutInsets = CGSize(
                width: max(0, window.frame.width - currentContentWidth),
                height: max(0, window.frame.height - currentContentHeight)
            )
            let maximumContentSize = CGSize(
                width: max(0, visibleFrame.width - layoutInsets.width),
                height: max(0, visibleFrame.height - layoutInsets.height)
            )
            let minimumWidth = min(minimumContentWidth, maximumContentSize.width)
            let minimumHeight = min(minimumContentHeight, maximumContentSize.height)

            window.contentMinSize = NSSize(width: minimumWidth, height: minimumHeight)
            window.minSize = WindowFramePolicy.frameSize(
                contentLayoutSize: CGSize(width: minimumWidth, height: minimumHeight),
                layoutInsets: layoutInsets,
                visibleFrame: visibleFrame
            )

            let input = WindowAutoFitState.Input(layout: layout, visibleFrame: visibleFrame,
                                                 layoutInsets: layoutInsets, hasMeasuredContent: hasMeasuredContent)
            guard context.coordinator.autoFit.shouldFit(input, isLiveResizing: window.inLiveResize) else { return }

            var targetWidth = max(currentContentWidth, minimumWidth)
            var targetHeight = max(currentContentHeight, minimumHeight)

            if shouldFitWidth, let contentWidth {
                targetWidth = max(minimumWidth, ceil(contentWidth))
            }
            if shouldFitHeight, contentHeight > 0 {
                targetHeight = max(minimumHeight, ceil(contentHeight))
            }

            targetWidth = min(targetWidth, maximumContentSize.width)
            targetHeight = min(targetHeight, maximumContentSize.height)

            let targetFrameSize = WindowFramePolicy.frameSize(
                contentLayoutSize: CGSize(width: targetWidth, height: targetHeight),
                layoutInsets: layoutInsets,
                visibleFrame: visibleFrame
            )
            let targetFrame = WindowFramePolicy.clampedFrame(
                currentFrame: window.frame,
                targetSize: targetFrameSize,
                visibleFrame: visibleFrame
            )
            guard abs(window.frame.minX - targetFrame.minX) > 1
                || abs(window.frame.minY - targetFrame.minY) > 1
                || abs(window.frame.width - targetFrame.width) > 1
                || abs(window.frame.height - targetFrame.height) > 1 else {
                return
            }
            window.setFrame(targetFrame, display: true, animate: false)
        }
    }
}
