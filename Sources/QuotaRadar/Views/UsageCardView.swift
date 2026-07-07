import SwiftUI

struct UsageCardView: View {
    var card: UsageCard
    var accentHex: String
    var primaryRingHex: String
    var secondaryRingHex: String
    var layout: LayoutPreset

    var body: some View {
        VStack(alignment: .leading, spacing: cardSpacing) {
            HStack {
                Label(card.title, systemImage: card.systemImage)
                    .font(.headline)
                    .foregroundStyle(.secondary)
                Spacer()
                if !card.trailingValue.isEmpty {
                    Text(card.trailingValue)
                        .font(.headline.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            }

            Text(card.primaryValue)
                .font(.system(size: primaryFontSize, weight: .bold, design: .rounded))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.65)

            if card.id == .planProgress {
                PlanProgressCardBody(progress: card.progress, note: card.note, accentHex: accentHex)
            } else if card.id == .resetCredits {
                ResetCreditsCardBody(note: card.note)
            } else if let meter = quotaMeter {
                QuotaMeterCardBody(meter: meter, note: card.note, lineLimit: layout.noteLineLimit)
            } else if let breakdown = card.breakdown {
                TokenBreakdownBar(breakdown: breakdown, accentHex: accentHex)
                TokenLegend(breakdown: breakdown)
            } else if let note = card.note {
                Capsule()
                    .fill(Color.white.opacity(0.14))
                    .frame(height: 12)
                Text(note)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(layout.noteLineLimit)
            } else {
                Capsule()
                    .fill(Color.white.opacity(0.14))
                    .frame(height: 10)
            }
        }
        .padding(layout.cardPadding)
        .frame(maxWidth: .infinity, minHeight: layout.cardHeight, maxHeight: layout.cardHeight, alignment: .topLeading)
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.42))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Color.white.opacity(0.12), lineWidth: 1)
        )
    }

    private var primaryFontSize: CGFloat {
        card.id == .planProgress ? layout.progressValueFontSize : layout.cardValueFontSize
    }

    private var cardSpacing: CGFloat {
        switch layout {
        case .compact: 10
        case .standard: 14
        case .spacious: 16
        }
    }

    private var quotaMeter: QuotaMeter? {
        guard [.tokenUsage, .weeklyQuota, .mcpUsage].contains(card.id) else {
            return nil
        }
        guard let percent = Self.percentValue(from: card.primaryValue) else {
            return nil
        }
        let fillHex: String
        switch card.id {
        case .tokenUsage:
            fillHex = primaryRingHex
        case .weeklyQuota:
            fillHex = secondaryRingHex
        case .mcpUsage:
            fillHex = accentHex
        default:
            fillHex = accentHex
        }
        return QuotaMeter(value: percent / 100, fillHex: fillHex)
    }

    private static func percentValue(from text: String) -> Double? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasSuffix("%") else {
            return nil
        }
        return Double(trimmed.dropLast())
    }
}

private struct QuotaMeter: Equatable {
    var value: Double
    var fillHex: String

    var clampedValue: Double {
        max(0, min(1, value))
    }
}

private struct QuotaMeterCardBody: View {
    var meter: QuotaMeter
    var note: String?
    var lineLimit: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Color.white.opacity(0.14))
                        .frame(height: 12)
                    Capsule()
                        .fill(Color(hex: meter.fillHex))
                        .frame(width: geometry.size.width * meter.clampedValue, height: 12)
                }
            }
            .frame(height: 12)

            if let note, !note.isEmpty {
                Text(note)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(lineLimit)
            }
        }
    }
}

private struct ResetCreditsCardBody: View {
    var note: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            if let note, !note.isEmpty {
                ForEach(Array(note.split(separator: "\n").prefix(3).enumerated()), id: \.offset) { _, line in
                    Text(String(line))
                        .font(.caption.monospacedDigit().weight(.semibold))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.72)
                }
            } else {
                Text("暂无可用重置卡")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct PlanProgressCardBody: View {
    var progress: PlanProgress?
    var note: String?
    var accentHex: String

    var body: some View {
        let markers = progress?.markers ?? []
        VStack(alignment: .leading, spacing: 12) {
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Color.white.opacity(0.14))
                        .frame(height: 12)
                    Capsule()
                        .fill(Color(hex: accentHex))
                        .frame(width: geometry.size.width * (progress?.progress ?? 0), height: 12)

                    ForEach(markers) { marker in
                        markerDot(marker, width: geometry.size.width)
                    }
                }
            }
            .frame(height: 12)

            HStack(spacing: 10) {
                ForEach(progress?.markers ?? fallbackMarkers) { marker in
                    markerView(label: marker.label, color: markerColorHex(marker.id))
                }
                Spacer(minLength: 0)
            }
            .frame(height: 16)

            if let note {
                Text(note)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
            }
        }
    }

    private func markerDot(_ marker: PlanMarker, width: CGFloat) -> some View {
        let x = max(0, min(width - 10, width * marker.position))
        return Circle()
            .fill(markerColor(marker.id))
            .overlay(Circle().stroke(Color.white.opacity(0.7), lineWidth: 1))
            .frame(width: 10, height: 10)
            .offset(x: x)
    }

    private func markerView(label: String, color: String) -> some View {
        HStack(spacing: 5) {
            Circle().fill(Color(hex: color)).frame(width: 8, height: 8)
            Text(label)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
        }
    }

    private var fallbackMarkers: [PlanMarker] {
        [
            PlanMarker(id: "plus", label: "Plus", position: 0),
            PlanMarker(id: "pro100", label: "Pro100", position: 0),
            PlanMarker(id: "pro200", label: "Pro200", position: 0)
        ]
    }

    private func markerColorHex(_ id: String) -> String {
        switch id {
        case "plus": "#60A5FA"
        case "pro100": "#2563EB"
        case "pro200": "#8B5CF6"
        default: accentHex
        }
    }

    private func markerColor(_ id: String) -> Color {
        Color(hex: markerColorHex(id))
    }
}

private struct TokenBreakdownBar: View {
    var breakdown: TokenBreakdown
    var accentHex: String

    var body: some View {
        GeometryReader { geometry in
            let total = max(1, breakdown.total)
            HStack(spacing: 0) {
                Rectangle()
                    .fill(Color(hex: accentHex))
                    .frame(width: geometry.size.width * Double(breakdown.uncachedInput) / Double(total))
                Rectangle()
                    .fill(Color(hex: "#8B5CF6"))
                    .frame(width: geometry.size.width * Double(breakdown.cachedInput) / Double(total))
                Rectangle()
                    .fill(Color(hex: "#F59E0B"))
                    .frame(width: geometry.size.width * Double(breakdown.output) / Double(total))
            }
            .clipShape(Capsule())
        }
        .frame(height: 12)
        .background(Color.white.opacity(0.12), in: Capsule())
    }
}

private struct TokenLegend: View {
    var breakdown: TokenBreakdown

    var body: some View {
        VStack(spacing: 6) {
            legendRow(color: "#1E88FF", label: "未缓存", value: breakdown.uncachedInput)
            legendRow(color: "#8B5CF6", label: "缓存", value: breakdown.cachedInput)
            legendRow(color: "#F59E0B", label: "输出", value: breakdown.output)
        }
    }

    private func legendRow(color: String, label: String, value: Int) -> some View {
        HStack {
            Circle().fill(Color(hex: color)).frame(width: 8, height: 8)
            Text(label)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            Spacer()
            Text(RadarFormatters.compactTokens(value))
                .font(.caption.monospacedDigit().weight(.bold))
                .foregroundStyle(.secondary)
        }
    }
}
