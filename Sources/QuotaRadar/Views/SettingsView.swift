import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var settings: AppSettings
    @EnvironmentObject private var store: UsageStore

    var body: some View {
        TabView {
            SettingsPage(title: "通用", subtitle: "刷新节奏和手动同步") {
                SettingsCard("刷新") {
                    SettingsRow(title: "自动刷新间隔", detail: "\(Int(settings.refreshIntervalMinutes)) 分钟") {
                        Stepper("", value: $settings.refreshIntervalMinutes, in: 1...60, step: 1)
                            .labelsHidden()
                    }

                    Divider()

                    Button {
                        Task { await store.refreshAll(force: true) }
                    } label: {
                        Label("立即刷新全部", systemImage: "arrow.clockwise")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
            .tabItem { Label("通用", systemImage: "gearshape") }

            ProviderSettingsPage(provider: .codex)
                .tabItem { Label("Codex", systemImage: "terminal") }

            ProviderSettingsPage(provider: .glm) {
                SettingsCard("GLM / ZAI API") {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("用于直接读取 `/monitor/usage/quota/limit`。默认也会读取同名环境变量。")
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        credentialField(title: "ANTHROPIC_AUTH_TOKEN") {
                            SecureField("token", text: $settings.glmAuthToken)
                                .textFieldStyle(.roundedBorder)
                        }

                        credentialField(title: "ANTHROPIC_BASE_URL") {
                            TextField("https://open.bigmodel.cn/api/anthropic", text: $settings.glmBaseURL)
                                .textFieldStyle(.roundedBorder)
                        }
                    }
                }
            }
            .tabItem { Label("GLM", systemImage: "sparkles") }
        }
        .frame(minWidth: 560, minHeight: 620)
    }

    private func credentialField<Content: View>(title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            content()
        }
    }
}

private struct ProviderSettingsPage<Extra: View>: View {
    @EnvironmentObject private var settings: AppSettings
    var provider: ProviderID
    @ViewBuilder var extra: () -> Extra

    init(provider: ProviderID, @ViewBuilder extra: @escaping () -> Extra = { EmptyView() }) {
        self.provider = provider
        self.extra = extra
    }

    var body: some View {
        SettingsPage(title: provider.displayName, subtitle: "配色和卡片显示") {
            SettingsCard("配色") {
                ColorSettingRow(title: "主圆环", color: colorBinding(\.ringPrimaryHex))
                Divider()
                ColorSettingRow(title: "副圆环", color: colorBinding(\.ringSecondaryHex))
                Divider()
                ColorSettingRow(title: "卡片强调色", color: colorBinding(\.cardAccentHex))
            }

            SettingsCard("显示卡片") {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 160), spacing: 10)], spacing: 10) {
                    ForEach(cards) { card in
                        Toggle(card.title, isOn: visibleBinding(card))
                            .toggleStyle(.checkbox)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }

            extra()
        }
    }

    private var cards: [UsageCardID] {
        switch provider {
        case .codex:
            [.today, .sevenDays, .total, .planProgress]
        case .glm:
            [.tokenUsage, .weeklyQuota, .mcpUsage, .multiplier]
        }
    }

    private func visibleBinding(_ card: UsageCardID) -> Binding<Bool> {
        Binding {
            settings.isVisible(card, for: provider)
        } set: { visible in
            settings.setVisible(visible, card: card, provider: provider)
        }
    }

    private func colorBinding(_ keyPath: WritableKeyPath<ProviderPreferences, String>) -> Binding<Color> {
        Binding {
            Color(hex: settings.preferences(for: provider)[keyPath: keyPath])
        } set: { color in
            var preferences = settings.preferences(for: provider)
            preferences[keyPath: keyPath] = color.toHex()
            settings.updatePreferences(preferences, for: provider)
        }
    }
}

private struct SettingsPage<Content: View>: View {
    var title: String
    var subtitle: String
    @ViewBuilder var content: () -> Content

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.title2.weight(.bold))
                    Text(subtitle)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                content()
            }
            .frame(maxWidth: 480, alignment: .leading)
            .padding(.horizontal, 32)
            .padding(.top, 28)
            .padding(.bottom, 36)
        }
        .background(Color(nsColor: .windowBackgroundColor))
    }
}

private struct SettingsCard<Content: View>: View {
    var title: String
    @ViewBuilder var content: () -> Content

    init(_ title: String, @ViewBuilder content: @escaping () -> Content) {
        self.title = title
        self.content = content
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(title)
                .font(.headline)
            content()
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.55))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Color.white.opacity(0.08), lineWidth: 1)
        )
    }
}

private struct SettingsRow<Trailing: View>: View {
    var title: String
    var detail: String
    @ViewBuilder var trailing: () -> Trailing

    var body: some View {
        HStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.body.weight(.semibold))
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            trailing()
        }
    }
}

private struct ColorSettingRow: View {
    var title: String
    @Binding var color: Color

    var body: some View {
        HStack {
            Text(title)
                .font(.body.weight(.semibold))
            Spacer()
            ColorPicker(title, selection: $color)
                .labelsHidden()
        }
    }
}
