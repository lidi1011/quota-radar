import SwiftUI

struct ProviderPanelView: View {
    var provider: ProviderID
    var snapshot: ProviderSnapshot?
    var displayedWindows: [UsageWindow]
    var state: ProviderLoadState
    var preferences: ProviderPreferences
    var layout: LayoutPreset
    var refresh: () -> Void

    private var gridCards: [UsageCard] {
        Self.renderedCards(snapshot: snapshot, preferences: preferences)
    }

    nonisolated static func hasRenderedCards(
        snapshot: ProviderSnapshot?,
        preferences: ProviderPreferences
    ) -> Bool {
        !renderedCards(snapshot: snapshot, preferences: preferences).isEmpty
    }

    nonisolated static func renderedCards(
        snapshot: ProviderSnapshot?,
        preferences: ProviderPreferences
    ) -> [UsageCard] {
        let visibleCards = (snapshot?.cards ?? []).filter {
            preferences.visibleCards.contains($0.id)
        }
        var cards = visibleCards.filter { card in
            ![.planProgress, .resetCredits, .subscriptionExpiry].contains(card.id)
        }

        if preferences.visibleCards.contains(.planProgress),
           let progress = snapshot?.progress {
            cards.append(
                UsageCard(
                    id: .planProgress,
                    title: progress.title,
                    systemImage: "chart.line.uptrend.xyaxis",
                    primaryValue: progress.currentValue,
                    trailingValue: "/ \(progress.maxValue)",
                    breakdown: nil,
                    note: "当前 \(Int(progress.progress * 100))% · Plus / Pro100 / Pro200 刻度",
                    progress: progress
                )
            )
        }

        if preferences.visibleCards.contains(.resetCredits),
           let resetCreditsCard = snapshot?.cards.first(where: { $0.id == .resetCredits }) {
            cards.append(resetCreditsCard)
        }

        if preferences.visibleCards.contains(.subscriptionExpiry),
           let subscriptionExpiryCard = snapshot?.cards.first(where: { $0.id == .subscriptionExpiry }) {
            cards.append(subscriptionExpiryCard)
        }
        return cards
    }

    var body: some View {
        VStack(alignment: .leading, spacing: layout.panelSpacing) {
            panelHeader

            if gridCards.isEmpty {
                centeredRingBlock
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
                windows: displayedWindows,
                primaryHex: preferences.ringPrimaryHex,
                secondaryHex: preferences.ringSecondaryHex,
                layout: layout
            )
            .frame(width: layout.ringSize, height: layout.ringSize)

            VStack(spacing: 8) {
                ForEach(Array(displayedWindows.enumerated()), id: \.element.id) { index, window in
                    HStack(spacing: 8) {
                        Circle()
                            .fill(Color(hex: ringColorHex(for: window, fallbackIndex: index)))
                            .frame(width: 8, height: 8)
                        if window.isCountdown {
                            Text("倒计时")
                                .font(layout.ringLabelFont)
                        } else {
                            Text(window.label)
                                .font(layout.ringLabelFont)
                            Text("重置")
                                .font(layout.ringLabelFont)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Text(window.resetText)
                            .font(layout.ringLabelFont.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    private func ringColorHex(for window: UsageWindow, fallbackIndex: Int) -> String {
        switch window.preferredRingRole {
        case .primary: preferences.ringPrimaryHex
        case .secondary: preferences.ringSecondaryHex
        case nil: fallbackIndex == 0 ? preferences.ringPrimaryHex : preferences.ringSecondaryHex
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
