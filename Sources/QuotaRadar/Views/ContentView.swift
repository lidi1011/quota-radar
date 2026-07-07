import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var settings: AppSettings
    @EnvironmentObject private var store: UsageStore
    @State private var contentHeight: CGFloat = 0

    private var visibleProviderCount: Int {
        visibleProviders.count
    }

    private var visibleProviders: [ProviderID] {
        ProviderID.allCases.filter { settings.isProviderVisible($0) }
    }

    var body: some View {
        GeometryReader { windowProxy in
            ScrollView(scrollAxes) {
                providerStack(containerWidth: windowProxy.size.width)
                .padding(.horizontal, settings.layoutPreset.contentHorizontalPadding)
                .padding(.vertical, settings.layoutPreset.contentVerticalPadding)
                .background(
                    GeometryReader { proxy in
                        Color.clear.preference(key: ContentHeightPreferenceKey.self, value: proxy.size.height)
                    }
                )
            }
            .onPreferenceChange(ContentHeightPreferenceKey.self) { height in
                contentHeight = height
            }
            .background(
                MainWindowSizeFitter(
                    contentWidth: fittedContentWidth,
                    contentHeight: contentHeight,
                    shouldFitWidth: fittedContentWidth != nil,
                    shouldFitHeight: visibleProviderCount == 1
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
    }

    private var scrollAxes: Axis.Set {
        settings.providerLayoutMode == .horizontal ? [.vertical, .horizontal] : [.vertical]
    }

    private var fittedContentWidth: CGFloat? {
        guard !visibleProviders.isEmpty,
              visibleProviders.allSatisfy({ settings.preferences(for: $0).visibleCards.isEmpty }) else {
            return nil
        }

        let layout = settings.layoutPreset
        let panelWidths = visibleProviders.map { _ in emptyProviderPanelWidth(layout: layout) }
        let panelWidth: CGFloat
        switch settings.providerLayoutMode {
        case .vertical:
            panelWidth = panelWidths.max() ?? 0
        case .horizontal:
            panelWidth = panelWidths.reduce(0, +)
                + CGFloat(max(0, panelWidths.count - 1)) * layout.contentSpacing
        }
        return panelWidth + layout.contentHorizontalPadding * 2
    }

    @ViewBuilder
    private func providerStack(containerWidth: CGFloat) -> some View {
        switch settings.providerLayoutMode {
        case .vertical:
            VStack(alignment: .leading, spacing: settings.layoutPreset.contentSpacing) {
                providerPanels()
            }
        case .horizontal:
            HStack(alignment: .top, spacing: settings.layoutPreset.contentSpacing) {
                providerPanels(containerWidth: containerWidth)
            }
        }
    }

    private func providerPanels(containerWidth: CGFloat? = nil) -> some View {
        ForEach(visibleProviders) { provider in
            ProviderPanelView(
                provider: provider,
                snapshot: store.snapshots[provider],
                state: store.states[provider] ?? .idle,
                preferences: settings.preferences(for: provider),
                layout: settings.layoutPreset,
                providerLayoutMode: settings.providerLayoutMode
            ) {
                Task { await store.refresh(provider) }
            }
            .frame(width: panelWidth(for: provider, containerWidth: containerWidth))
        }
    }

    private func panelWidth(for provider: ProviderID, containerWidth: CGFloat?) -> CGFloat? {
        let layout = settings.layoutPreset
        guard !settings.preferences(for: provider).visibleCards.isEmpty else {
            return emptyProviderPanelWidth(layout: layout)
        }

        guard settings.providerLayoutMode == .horizontal, let containerWidth else {
            return nil
        }
        return horizontalProviderPanelWidth(containerWidth: containerWidth)
    }

    private func horizontalProviderPanelWidth(containerWidth: CGFloat) -> CGFloat {
        let layout = settings.layoutPreset
        let ringWidth = layout.ringColumnWidth + layout.panelPadding * 2
        let availableWidth = containerWidth - layout.contentHorizontalPadding * 2 - layout.contentSpacing
        let halfWindowWidth = max(0, availableWidth / 2)
        let twoCardGridWidth = layout.cardMinWidth * 2 + layout.cardSpacing + layout.panelPadding * 2
        return max(halfWindowWidth, twoCardGridWidth, ringWidth)
    }

    private func emptyProviderPanelWidth(layout: LayoutPreset) -> CGFloat {
        let ringWidth = layout.ringColumnWidth + layout.panelPadding * 2
        return max(ringWidth, emptyProviderPanelSquareWidth(layout: layout))
    }

    private func emptyProviderPanelSquareWidth(layout: LayoutPreset) -> CGFloat {
        let headerHeight: CGFloat
        let legendHeight: CGFloat
        switch layout {
        case .compact:
            headerHeight = 42
            legendHeight = 42
        case .standard:
            headerHeight = 50
            legendHeight = 50
        case .spacious:
            headerHeight = 58
            legendHeight = 58
        }

        return layout.panelPadding * 2
            + headerHeight
            + layout.panelSpacing
            + layout.ringSize
            + 12
            + legendHeight
    }

}

private struct ContentHeightPreferenceKey: PreferenceKey {
    static let defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

private struct MainWindowSizeFitter: NSViewRepresentable {
    private static let minimumContentSize = NSSize(width: 320, height: 360)

    var contentWidth: CGFloat?
    var contentHeight: CGFloat
    var shouldFitWidth: Bool
    var shouldFitHeight: Bool

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context: Context) -> NSView {
        NSView()
    }

    func updateNSView(_ view: NSView, context: Context) {
        guard (shouldFitWidth && contentWidth != nil) || (shouldFitHeight && contentHeight > 0) else {
            return
        }

        DispatchQueue.main.async {
            guard let window = view.window else { return }
            let currentContentWidth = window.contentLayoutRect.width
            let currentContentHeight = window.contentLayoutRect.height
            var targetWidth = currentContentWidth > 0 ? currentContentWidth : window.frame.width
            var targetHeight = currentContentHeight > 0 ? currentContentHeight : window.frame.height

            if shouldFitWidth, let contentWidth {
                targetWidth = max(Self.minimumContentSize.width, ceil(contentWidth))
            }
            if shouldFitHeight, contentHeight > 0 {
                targetHeight = max(Self.minimumContentSize.height, ceil(contentHeight))
            }

            guard abs(context.coordinator.lastAppliedWidth - targetWidth) > 1
                || abs(context.coordinator.lastAppliedHeight - targetHeight) > 1 else {
                return
            }

            context.coordinator.lastAppliedWidth = targetWidth
            context.coordinator.lastAppliedHeight = targetHeight

            if abs(currentContentWidth - targetWidth) > 12 || abs(currentContentHeight - targetHeight) > 12 {
                let targetContentSize = NSSize(width: targetWidth, height: targetHeight)
                let contentMinimumSize = NSSize(
                    width: min(Self.minimumContentSize.width, targetWidth),
                    height: min(Self.minimumContentSize.height, targetHeight)
                )
                window.contentMinSize = contentMinimumSize
                window.minSize = window.frameRect(
                    forContentRect: NSRect(origin: .zero, size: contentMinimumSize)
                ).size

                let targetFrameSize = window.frameRect(
                    forContentRect: NSRect(origin: .zero, size: targetContentSize)
                ).size
                let currentFrame = window.frame
                let targetFrame = NSRect(
                    x: currentFrame.minX,
                    y: currentFrame.maxY - targetFrameSize.height,
                    width: targetFrameSize.width,
                    height: targetFrameSize.height
                )
                window.setFrame(targetFrame, display: true, animate: false)
            }
        }
    }

    final class Coordinator {
        var lastAppliedWidth: CGFloat = 0
        var lastAppliedHeight: CGFloat = 0
    }
}
