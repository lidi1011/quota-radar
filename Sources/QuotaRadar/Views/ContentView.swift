import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var settings: AppSettings
    @EnvironmentObject private var store: UsageStore

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                ForEach(ProviderID.allCases) { provider in
                    ProviderPanelView(
                        provider: provider,
                        snapshot: store.snapshots[provider],
                        state: store.states[provider] ?? .idle,
                        preferences: settings.preferences(for: provider)
                    ) {
                        Task { await store.refresh(provider) }
                    }
                }
            }
            .padding(.horizontal, 22)
            .padding(.vertical, 18)
        }
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

#Preview {
    ContentView()
        .environmentObject(AppSettings())
        .environmentObject(UsageStore(settings: AppSettings()))
        .frame(width: 1180, height: 860)
}
