import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var settings: AppSettings
    @EnvironmentObject private var store: UsageStore

    var body: some View {
        TabView {
            SettingsPage(title: "通用", subtitle: "刷新节奏和手动同步") {
                SettingsCard("布局") {
                    SettingsRow(title: "布局尺寸", detail: "控制主窗口卡片、圆环和间距") {
                        Picker("布局尺寸", selection: $settings.layoutPreset) {
                            ForEach(LayoutPreset.allCases) { preset in
                                Text(preset.title).tag(preset)
                            }
                        }
                        .labelsHidden()
                        .pickerStyle(.segmented)
                        .frame(width: 220)
                    }
                }

                SettingsCard("Provider 展示") {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 160), spacing: 10)], spacing: 10) {
                        ForEach(ProviderID.allCases) { provider in
                            Toggle(provider.displayName, isOn: providerVisibleBinding(provider))
                                .toggleStyle(.checkbox)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                }

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

            ProviderSettingsPage(provider: .codex) {
                SubscriptionExpirySettingCard(
                    providerName: ProviderID.codex.displayName,
                    rule: $settings.codexManualSubscriptionRule
                )
            }
                .tabItem { Label("Codex", systemImage: "terminal") }

            ProviderSettingsPage(provider: .glm) {
                SubscriptionExpirySettingCard(
                    providerName: ProviderID.glm.displayName,
                    rule: $settings.glmManualSubscriptionRule
                )

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

    private func providerVisibleBinding(_ provider: ProviderID) -> Binding<Bool> {
        Binding {
            settings.isProviderVisible(provider)
        } set: { visible in
            settings.setProviderVisible(visible, provider: provider)
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
            [.today, .sevenDays, .total, .planProgress, .resetCredits, .subscriptionExpiry]
        case .glm:
            [.tokenUsage, .weeklyQuota, .mcpUsage, .multiplier, .subscriptionExpiry]
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

private struct SubscriptionExpirySettingCard: View {
    var providerName: String
    @Binding var rule: ManualSubscriptionRule?

    var body: some View {
        SettingsCard("订阅到期兜底") {
            VStack(alignment: .leading, spacing: 12) {
                Text("自动读取不到 \(providerName) 订阅到期时间时，卡片会按这里的每月续费日计算。")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                if rule == nil {
                    Button {
                        rule = .monthly(day: 15)
                    } label: {
                        Label("设置每月续费日", systemImage: "calendar.badge.plus")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                } else {
                    SettingsRow(title: "续费日", detail: "每月 \(currentDay) 日") {
                        Picker("续费日", selection: dayBinding) {
                            ForEach(1...31, id: \.self) { day in
                                Text("每月 \(day) 日").tag(day)
                            }
                        }
                        .labelsHidden()
                        .pickerStyle(.menu)
                        .frame(width: 128)
                    }

                    Button(role: .destructive) {
                        rule = nil
                    } label: {
                        Label("清空续费规则", systemImage: "trash")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                }
            }
        }
    }

    private var currentDay: Int {
        switch rule {
        case .monthly(let day):
            return min(31, max(1, day))
        case .fixedDate(let date):
            return RadarFormatters.localCalendar.component(.day, from: date)
        case .none:
            return 15
        }
    }

    private var dayBinding: Binding<Int> {
        Binding {
            currentDay
        } set: { newValue in
            rule = .monthly(day: newValue)
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
