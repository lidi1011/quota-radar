import AppKit
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
    }
}

@main
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
                .frame(minWidth: 420, minHeight: 360)
                .task {
                    await store.refreshAll(force: true)
                    store.startAutoRefresh()
                }
                .onChange(of: settings.refreshIntervalMinutes) { _, _ in
                    store.startAutoRefresh()
                }
        }
        .windowResizability(.contentMinSize)
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
