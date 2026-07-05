import SwiftUI

struct ProviderPanelView: View {
    var provider: ProviderID
    var snapshot: ProviderSnapshot?
    var state: ProviderLoadState
    var preferences: ProviderPreferences
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

    private var gridCards: [UsageCard] {
        var cards = visibleCards.filter { $0.id != .planProgress && $0.id != .resetCredits }
        if let progressCard {
            cards.append(progressCard)
        }
        if let resetCreditsCard {
            cards.append(resetCreditsCard)
        }
        return cards
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            panelHeader

            if gridCards.isEmpty {
                HStack {
                    Spacer(minLength: 0)
                    ringBlock
                        .frame(width: 270)
                    Spacer(minLength: 0)
                }
            } else {
                ViewThatFits(in: .horizontal) {
                    HStack(alignment: .center, spacing: 26) {
                        ringBlock
                            .frame(width: 270)
                        dashboardBlock
                    }

                    VStack(alignment: .leading, spacing: 18) {
                        ringBlock
                        dashboardBlock
                    }
                }
            }
        }
        .fixedSize(horizontal: false, vertical: true)
        .padding(20)
        .background(panelBackground)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Color.white.opacity(0.13), lineWidth: 1)
        )
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
                secondaryHex: preferences.ringSecondaryHex
            )
            .frame(width: 220, height: 220)

            VStack(spacing: 8) {
                ForEach(snapshot?.windows ?? []) { window in
                    HStack(spacing: 8) {
                        Circle()
                            .fill(window.id == (snapshot?.windows.first?.id ?? "") ? Color(hex: preferences.ringPrimaryHex) : Color(hex: preferences.ringSecondaryHex))
                            .frame(width: 8, height: 8)
                        Text(window.label)
                            .font(.callout.weight(.bold))
                        Text("重置")
                            .font(.callout.weight(.semibold))
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text(window.resetText)
                            .font(.callout.monospacedDigit().weight(.semibold))
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    private var dashboardBlock: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 230), spacing: 16)], spacing: 16) {
                ForEach(gridCards) { card in
                    UsageCardView(card: card, accentHex: preferences.cardAccentHex)
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
