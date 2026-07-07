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
        ScrollView(scrollAxes) {
            providerStack
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
            MainWindowHeightFitter(
                contentHeight: contentHeight,
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

    private var scrollAxes: Axis.Set {
        settings.providerLayoutMode == .horizontal ? [.vertical, .horizontal] : [.vertical]
    }

    @ViewBuilder
    private var providerStack: some View {
        switch settings.providerLayoutMode {
        case .vertical:
            VStack(alignment: .leading, spacing: settings.layoutPreset.contentSpacing) {
                providerPanels
            }
        case .horizontal:
            HStack(alignment: .top, spacing: settings.layoutPreset.contentSpacing) {
                providerPanels
            }
        }
    }

    private var providerPanels: some View {
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
        }
    }

}

private struct ContentHeightPreferenceKey: PreferenceKey {
    static let defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

private struct MainWindowHeightFitter: NSViewRepresentable {
    var contentHeight: CGFloat
    var shouldFitHeight: Bool

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context: Context) -> NSView {
        NSView()
    }

    func updateNSView(_ view: NSView, context: Context) {
        guard shouldFitHeight, contentHeight > 0 else {
            return
        }

        DispatchQueue.main.async {
            guard let window = view.window else { return }
            let targetHeight = ceil(contentHeight)
            guard abs(context.coordinator.lastAppliedHeight - targetHeight) > 1 else { return }

            context.coordinator.lastAppliedHeight = targetHeight
            let width = window.contentLayoutRect.width > 0 ? window.contentLayoutRect.width : window.frame.width
            let currentContentHeight = window.contentLayoutRect.height

            if abs(currentContentHeight - targetHeight) > 12 {
                window.setContentSize(NSSize(width: width, height: targetHeight))
            }
        }
    }

    final class Coordinator {
        var lastAppliedHeight: CGFloat = 0
    }
}
