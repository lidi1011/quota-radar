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
                ring(
                    value: first.remainingPercent / 100,
                    color: Color(hex: ringColorHex(for: first, fallbackIndex: 0)),
                    lineWidth: layout.ringLineWidth
                )
            }

            if windows.count > 1 {
                ringBackground(lineWidth: layout.ringLineWidth)
                    .frame(width: innerRingSize, height: innerRingSize)

                ring(
                    value: windows[1].remainingPercent / 100,
                    color: Color(hex: ringColorHex(for: windows[1], fallbackIndex: 1)),
                    lineWidth: layout.ringLineWidth
                )
                    .frame(width: innerRingSize, height: innerRingSize)
            }

            VStack(spacing: 6) {
                ForEach(Array(windows.prefix(2).enumerated()), id: \.element.id) { index, window in
                    HStack(spacing: 6) {
                        Text(window.label)
                            .foregroundStyle(Color(hex: ringColorHex(for: window, fallbackIndex: index)))
                            .font(layout.ringLabelFont)
                        Text(percentText(for: window))
                            .font(layout.ringValueFont)
                    }
                }
            }
        }
    }

    private var innerRingSize: CGFloat {
        layout.ringSize * 0.67
    }

    private func percentText(for window: UsageWindow) -> String {
        if window.isCountdown {
            RadarFormatters.countdownPercent(window.remainingPercent)
        } else {
            RadarFormatters.percent(window.remainingPercent)
        }
    }

    private func ringColorHex(for window: UsageWindow, fallbackIndex: Int) -> String {
        switch window.preferredRingRole {
        case .primary: primaryHex
        case .secondary: secondaryHex
        case nil: fallbackIndex == 0 ? primaryHex : secondaryHex
        }
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
