import SwiftUI

struct PlanProgressView: View {
    var progress: PlanProgress
    var accentHex: String

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Label(progress.title, systemImage: "chart.line.uptrend.xyaxis")
                    .font(.title3.weight(.bold))
                Spacer()
                Text(progress.currentValue)
                    .font(.title.monospacedDigit().weight(.bold))
                Text("/ \(progress.maxValue)")
                    .font(.headline.monospacedDigit().weight(.bold))
                    .foregroundStyle(.secondary)
            }

            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Color.white.opacity(0.13))
                        .frame(height: 14)
                    Capsule()
                        .fill(Color(hex: accentHex))
                        .frame(width: geometry.size.width * progress.progress, height: 14)

                    ForEach(progress.markers) { marker in
                        Circle()
                            .fill(Color(hex: "#A78BFA"))
                            .overlay(Circle().stroke(Color.white.opacity(0.8), lineWidth: 1))
                            .frame(width: 12, height: 12)
                            .offset(x: max(0, min(geometry.size.width - 12, geometry.size.width * marker.position)))
                    }
                }
            }
            .frame(height: 18)

            HStack(spacing: 14) {
                ForEach(progress.markers) { marker in
                    Label(marker.label, systemImage: "circle.fill")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }
        }
        .padding(18)
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.42))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Color.white.opacity(0.12), lineWidth: 1)
        )
    }
}
