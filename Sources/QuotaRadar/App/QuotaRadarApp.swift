import AppKit
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
    }
}

@main
enum QuotaRadarEntry {
    @MainActor static func main() {
        if CommandLine.arguments.contains("--claude-statusline") {
            exit(ClaudeStatusLineBridge().run())
        }
        QuotaRadarApp.main()
    }
}

struct QuotaRadarApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var settings = AppSettings()
    @StateObject private var store: UsageStore

    init() {
        let settings = AppSettings()
        _settings = StateObject(wrappedValue: settings)
        _store = StateObject(wrappedValue: UsageStore(settings: settings))
    }

    var body: some Scene {
        WindowGroup("额度雷达") {
            ContentView()
                .environmentObject(settings)
                .environmentObject(store)
                .task {
                    await store.refreshAll(force: true)
                    store.startAutoRefresh()
                }
                .onChange(of: settings.refreshIntervalMinutes) { _, _ in
                    store.startAutoRefresh()
                }
        }
        .windowResizability(.contentMinSize)
        .windowToolbarStyle(.unifiedCompact)
        .commands {
            CommandMenu("额度雷达") {
                Button("刷新全部") {
                    Task { await store.refreshAll(force: true) }
                }
                .keyboardShortcut("r", modifiers: [.command])

                SettingsLink {
                    Text("设置...")
                }
                .keyboardShortcut(",", modifiers: [.command])
            }
        }

        Settings {
            SettingsView()
                .environmentObject(settings)
                .environmentObject(store)
                .frame(width: 560, height: 620)
        }
    }
}
