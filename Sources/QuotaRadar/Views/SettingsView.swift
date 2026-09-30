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

                    Divider()

                    SettingsRow(title: "排列方向", detail: "控制服务的上下或左右排列") {
                        Picker("排列方向", selection: $settings.providerLayoutMode) {
                            ForEach(ProviderLayoutMode.allCases) { mode in
                                Text(mode.title).tag(mode)
                            }
                        }
                        .labelsHidden()
                        .pickerStyle(.segmented)
                        .frame(width: 160)
                    }
                }

                SettingsCard("圆环显示与顺序") {
                    Text("上下箭头调整横竖布局的顺序；取消勾选仅隐藏圆环，保留位置，不停止额度读取。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    ForEach(settings.providerOrder) { provider in
                        HStack {
                            Toggle(provider.displayName, isOn: providerVisibleBinding(provider))
                                .toggleStyle(.checkbox)
                            if !settings.isProviderVisible(provider) {
                                Text("已隐藏").font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Button { settings.moveProvider(provider, by: -1) } label: {
                                Image(systemName: "arrow.up")
                            }
                            .help("上移 \(provider.displayName)")
                            .accessibilityLabel("上移 \(provider.displayName)")
                            .disabled(settings.providerOrder.first == provider)
                            Button { settings.moveProvider(provider, by: 1) } label: {
                                Image(systemName: "arrow.down")
                            }
                            .help("下移 \(provider.displayName)")
                            .accessibilityLabel("下移 \(provider.displayName)")
                            .disabled(settings.providerOrder.last == provider)
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
                SettingsCard("额度圆环") {
                    SettingsRow(title: "重置周期", detail: "7 天模式显示额度外环与重置倒计时内环；兼容模式保留原双额度圆环") {
                        Picker("重置周期", selection: $settings.codexQuotaRingMode) {
                            ForEach(CodexQuotaRingMode.allCases) { mode in
                                Text(mode.title).tag(mode)
                            }
                        }
                        .labelsHidden()
                        .pickerStyle(.segmented)
                        .frame(width: 220)
                    }
                }

                SettingsCard("Codex 订阅读取") {
                    VStack(alignment: .leading, spacing: 10) {
                        Toggle(isOn: $settings.codexRemoteSubscriptionLookupEnabled) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("允许远程读取订阅到期")
                                    .font(.callout.weight(.semibold))
                                Text("默认关闭。开启后会使用 Codex access token 请求 chatgpt.com backend；关闭时只使用本机 app-server 和手动兜底。")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .toggleStyle(.switch)
                    }
                }

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

            ProviderSettingsPage(provider: .claude) {
                ClaudeIntegrationSettings()
            }
            .tabItem { Label("Claude Code", systemImage: "circle.dotted.circle") }
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

private struct ClaudeIntegrationSettings: View {
    @EnvironmentObject private var settings: AppSettings
    @EnvironmentObject private var store: UsageStore
    @State private var message = ""
    @State private var showsReadingDetails = false

    var body: some View {
        SettingsCard("圆环额度来源") {
            Picker("数据来源", selection: $settings.claudeQuotaSource) {
                ForEach(ClaudeQuotaSource.allCases, id: \.self) { source in
                    Text(source.title).tag(source)
                }
            }
            .pickerStyle(.segmented)
            .onChange(of: settings.claudeQuotaSource) { _, _ in
                message = ""
                showsReadingDetails = false
                store.changeClaudeSource()
            }
        }
        if settings.claudeQuotaSource == .desktop {
            SettingsCard("跟随 Claude 桌面端") {
                VStack(alignment: .leading, spacing: 10) {
                    Toggle("启用桌面端额度读取", isOn: $settings.claudeDesktopReadingEnabled)
                        .onChange(of: settings.claudeDesktopReadingEnabled) { _, _ in store.changeClaudeSource() }
                    Text(settings.claudeDesktopReadingEnabled
                         ? store.snapshots[.claude]?.statusMessage ?? "等待首次读取"
                         : "已暂停读取")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text("跟随桌面端登录账号查询额度；首次读取可能需要钥匙串授权。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Button("刷新桌面端额度") { Task { await store.refresh(.claude) } }
                        .buttonStyle(.borderedProminent)
                        .disabled(!settings.claudeDesktopReadingEnabled || store.states[.claude] == .loading)
                    DisclosureGroup("读取说明", isExpanded: $showsReadingDetails) {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("关闭后停止读取登录信息和查询额度，并清空圆环显示。")
                            Text("查询当前组织的 5 小时和 7 天额度。切换账号后，点击刷新或等待下一次自动刷新。")
                            Text("凭据不写入额度缓存或日志；CLI 采集配置保持不变。")
                            Text("依赖 Claude 内部网页接口；登录失效、网页验证或限流时会显示提示。请求至少间隔 1 分钟，失败后等待 5 分钟。")
                        }
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.top, 6)
                    }
                }
            }
        } else {
            SettingsCard("CLI 本地额度采集") {
                VStack(alignment: .leading, spacing: 10) {
                    Toggle("启用 CLI 额度读取", isOn: $settings.claudeCLIReadingEnabled)
                        .onChange(of: settings.claudeCLIReadingEnabled) { _, _ in store.changeClaudeSource() }
                    Text(settings.claudeCLIReadingEnabled
                         ? store.snapshots[.claude]?.statusMessage ?? "等待首次读取"
                         : "已暂停读取")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text("关闭仅暂停读取本地快照；撤销采集配置请用“停用 CLI 采集”。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Button("接入 / 更新采集器") {
                        perform {
                            guard let executable = Bundle.main.executableURL else { return }
                            try ClaudeStatusLineBridge().install(executable: executable)
                            message = "已接入。请在 Claude Code 中继续使用；若未更新，请重新打开会话。"
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    HStack {
                        Button("清除会话绑定") {
                            perform {
                                try ClaudeStatusLineBridge().resetSource()
                                message = "已清空来源，等待首个返回额度的会话。"
                            }
                        }
                        Button("停用 CLI 采集") {
                            perform {
                                try ClaudeStatusLineBridge().uninstall()
                                message = "已停用 CLI 采集，并恢复接入前的状态栏配置。"
                            }
                        }
                    }
                    if !message.isEmpty {
                        Text(message)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                    }
                    DisclosureGroup("读取说明", isExpanded: $showsReadingDetails) {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("接入后，在终端 Claude Code 中完成一次对话即可读取订阅额度。保留现有状态栏，只保存额度和重置时间。")
                            Text("绑定首个提供额度的会话；切换会话或账号时，点击“清除会话绑定”，再在目标会话中继续使用。")
                            Text("刷新仅重读快照。超过 15 分钟未变化会标为历史；API 或第三方服务可能不提供订阅额度。")
                            Text("关闭读取会清空圆环，但保留采集器和会话绑定；“停用 CLI 采集”会撤销采集器并恢复接入前的状态栏配置。")
                        }
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.top, 6)
                    }
                }
            }
        }
    }

    private func perform(_ action: () throws -> Void) {
        do {
            try action()
            Task { await store.refresh(.claude) }
        } catch {
            message = error.localizedDescription
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
        SettingsPage(title: provider.displayName, subtitle: provider == .claude ? "5 小时与 7 天剩余额度" : "圆环、配色和卡片显示") {
            SettingsCard("配色") {
                ColorSettingRow(title: "主圆环", color: colorBinding(\.ringPrimaryHex))
                Divider()
                ColorSettingRow(title: "副圆环", color: colorBinding(\.ringSecondaryHex))
                if provider != .claude {
                    Divider()
                    ColorSettingRow(title: "卡片强调色", color: colorBinding(\.cardAccentHex))
                }
            }

            if !cards.isEmpty {
                SettingsCard("显示卡片") {
                    VStack(alignment: .leading, spacing: 12) {
                        Toggle("全选/全不选", isOn: allCardsVisibleBinding)
                            .toggleStyle(.checkbox)
                            .font(.callout.weight(.semibold))

                        Divider()

                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 160), spacing: 10)], spacing: 10) {
                            ForEach(cards) { card in
                                Toggle(card.title, isOn: visibleBinding(card))
                                    .toggleStyle(.checkbox)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                        }
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
        case .claude:
            []
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

    private var allCardsVisibleBinding: Binding<Bool> {
        Binding {
            Set(cards).isSubset(of: settings.preferences(for: provider).visibleCards)
        } set: { visible in
            var preferences = settings.preferences(for: provider)
            if visible {
                preferences.visibleCards.formUnion(cards)
            } else {
                preferences.visibleCards.subtract(cards)
            }
            settings.updatePreferences(preferences, for: provider)
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
