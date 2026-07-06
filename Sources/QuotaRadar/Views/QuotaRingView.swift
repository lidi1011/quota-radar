import SwiftUI

struct QuotaRingView: View {
    var windows: [UsageWindow]
    var primaryHex: String
    var secondaryHex: String
    var layout: LayoutPreset

    var body: some View {
        ZStack {
            ringBackground(lineWidth: layout.ringLineWidth)

            if let first = windows.first {
                ring(value: first.remainingPercent / 100, color: Color(hex: primaryHex), lineWidth: layout.ringLineWidth)
            }

            ringBackground(lineWidth: layout.ringLineWidth)
                .frame(width: innerRingSize, height: innerRingSize)

            if windows.count > 1 {
                ring(value: windows[1].remainingPercent / 100, color: Color(hex: secondaryHex), lineWidth: layout.ringLineWidth)
                    .frame(width: innerRingSize, height: innerRingSize)
            }

            VStack(spacing: 6) {
                ForEach(Array(windows.prefix(2).enumerated()), id: \.element.id) { index, window in
                    HStack(spacing: 6) {
                        Text(window.label)
                            .foregroundStyle(index == 0 ? Color(hex: primaryHex) : Color(hex: secondaryHex))
                            .font(layout.ringLabelFont)
                        Text(RadarFormatters.percent(window.remainingPercent))
                            .font(layout.ringValueFont)
                    }
                }
            }
        }
    }

    private var innerRingSize: CGFloat {
        layout.ringSize * 0.67
    }

    private func ringBackground(lineWidth: CGFloat) -> some View {
        Circle()
            .stroke(Color.black.opacity(0.22), lineWidth: lineWidth)
    }

    private func ring(value: Double, color: Color, lineWidth: CGFloat) -> some View {
        let clamped = max(0.02, min(1, value))
        let lowQuotaLightness = (1 - clamped) * 0.34
        let startColor = color.mixed(with: .white, fraction: lowQuotaLightness)
        let endColor = color.mixed(with: .white, fraction: 0.28 + lowQuotaLightness)

        return Circle()
            .trim(from: 0, to: clamped)
            .stroke(
                AngularGradient(
                    colors: [startColor, endColor, startColor],
                    center: .center,
                    startAngle: .degrees(-90),
                    endAngle: .degrees(270)
                ),
                style: StrokeStyle(lineWidth: lineWidth, lineCap: .round)
            )
            .rotationEffect(.degrees(-90))
            .shadow(color: startColor.opacity(0.24), radius: 10, x: 0, y: 4)
    }
}
