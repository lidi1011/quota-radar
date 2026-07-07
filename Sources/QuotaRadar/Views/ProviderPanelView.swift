import SwiftUI

struct ProviderPanelView: View {
    var provider: ProviderID
    var snapshot: ProviderSnapshot?
    var state: ProviderLoadState
    var preferences: ProviderPreferences
    var layout: LayoutPreset
    var providerLayoutMode: ProviderLayoutMode = .vertical
    var refresh: () -> Void

    private var visibleCards: [UsageCard] {
        (snapshot?.cards ?? []).filter { preferences.visibleCards.contains($0.id) }
    }

    private var progressCard: UsageCard? {
        guard preferences.visibleCards.contains(.planProgress),
              let progress = snapshot?.progress else {
            return nil
        }
        return UsageCard(
            id: .planProgress,
            title: progress.title,
            systemImage: "chart.line.uptrend.xyaxis",
            primaryValue: progress.currentValue,
            trailingValue: "/ \(progress.maxValue)",
            breakdown: nil,
            note: "当前 \(Int(progress.progress * 100))% · Plus / Pro100 / Pro200 刻度",
            progress: progress
        )
    }

    private var resetCreditsCard: UsageCard? {
        guard preferences.visibleCards.contains(.resetCredits) else {
            return nil
        }
        return snapshot?.cards.first { $0.id == .resetCredits }
    }

    private var subscriptionExpiryCard: UsageCard? {
        guard preferences.visibleCards.contains(.subscriptionExpiry) else {
            return nil
        }
        return snapshot?.cards.first { $0.id == .subscriptionExpiry }
    }

    private var gridCards: [UsageCard] {
        var cards = visibleCards.filter { card in
            ![.planProgress, .resetCredits, .subscriptionExpiry].contains(card.id)
        }
        if let progressCard {
            cards.append(progressCard)
        }
        if let resetCreditsCard {
            cards.append(resetCreditsCard)
        }
        if let subscriptionExpiryCard {
            cards.append(subscriptionExpiryCard)
        }
        return cards
    }

    var body: some View {
        VStack(alignment: .leading, spacing: layout.panelSpacing) {
            panelHeader

            if gridCards.isEmpty {
                centeredRingBlock
            } else if providerLayoutMode == .horizontal {
                verticalPanelContent
            } else {
                ViewThatFits(in: .horizontal) {
                    HStack(alignment: .center, spacing: layout.horizontalBlockSpacing) {
                        ringBlock
                            .frame(width: layout.ringColumnWidth)
                        dashboardBlock
                    }

                    VStack(alignment: .leading, spacing: layout.panelSpacing) {
                        centeredRingBlock
                        dashboardBlock
                    }
                }
            }
        }
        .fixedSize(horizontal: false, vertical: true)
        .padding(layout.panelPadding)
        .background(panelBackground)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Color.white.opacity(0.13), lineWidth: 1)
        )
    }

    private var verticalPanelContent: some View {
        VStack(alignment: .leading, spacing: layout.panelSpacing) {
            centeredRingBlock
            dashboardBlock
        }
    }

    private var centeredRingBlock: some View {
        HStack {
            Spacer(minLength: 0)
            ringBlock
                .frame(width: layout.ringColumnWidth)
            Spacer(minLength: 0)
        }
    }

    private var panelHeader: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 10) {
                    Circle()
                        .fill(Color(hex: preferences.cardAccentHex))
                        .frame(width: 10, height: 10)
                    Text(provider.displayName)
                        .font(.title2.weight(.bold))
                }
                Text(statusLine)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .minimumScaleFactor(0.78)
            }

            Spacer()

            Button(action: refresh) {
                Label("刷新", systemImage: state == .loading ? "hourglass" : "arrow.clockwise")
            }
            .buttonStyle(.bordered)
            .disabled(state == .loading)
        }
    }

    private var ringBlock: some View {
        VStack(spacing: 12) {
            QuotaRingView(
                windows: snapshot?.windows ?? [
                    .placeholder(id: "primary", label: "主"),
                    .placeholder(id: "secondary", label: "次")
                ],
                primaryHex: preferences.ringPrimaryHex,
                secondaryHex: preferences.ringSecondaryHex,
                layout: layout
            )
            .frame(width: layout.ringSize, height: layout.ringSize)

            VStack(spacing: 8) {
                ForEach(snapshot?.windows ?? []) { window in
                    HStack(spacing: 8) {
                        Circle()
                            .fill(window.id == (snapshot?.windows.first?.id ?? "") ? Color(hex: preferences.ringPrimaryHex) : Color(hex: preferences.ringSecondaryHex))
                            .frame(width: 8, height: 8)
                        Text(window.label)
                            .font(layout.ringLabelFont)
                        Text("重置")
                            .font(layout.ringLabelFont)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text(window.resetText)
                            .font(layout.ringLabelFont.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    private var dashboardBlock: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: layout.cardMinWidth), spacing: layout.cardSpacing)], spacing: layout.cardSpacing) {
                ForEach(gridCards) { card in
                    UsageCardView(
                        card: card,
                        accentHex: preferences.cardAccentHex,
                        primaryRingHex: preferences.ringPrimaryHex,
                        secondaryRingHex: preferences.ringSecondaryHex,
                        layout: layout
                    )
                }
        }
    }

    private var panelBackground: some ShapeStyle {
        LinearGradient(
            colors: [
                Color.black.opacity(0.26),
                Color(hex: preferences.cardAccentHex).opacity(0.18),
                Color(nsColor: .controlBackgroundColor).opacity(0.36)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    private var stateIsFailure: Bool {
        if case .failed = state { return true }
        return false
    }

    private var statusLine: String {
        if case .failed(let message) = state {
            return message
        }
        if let message = snapshot?.statusMessage, !message.isEmpty {
            return message
        }
        return state.label
    }
}
