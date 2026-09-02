import SwiftUI

struct ScanningRingView: View {
    let fraction: Double
    let title: String
    let subtitle: String
    var isIndeterminate: Bool = false

    @State private var spinAngle: Double = 0

    var body: some View {
        StableChartContainer { chartSide in
            let radius = chartSide * 0.38

            ZStack {
                Circle()
                    .stroke(Color.primary.opacity(0.08), lineWidth: 10)
                    .frame(width: radius * 2, height: radius * 2)

                if isIndeterminate {
                    Circle()
                        .trim(from: 0, to: 0.28)
                        .stroke(
                            Color.accentColor,
                            style: StrokeStyle(lineWidth: 10, lineCap: .round)
                        )
                        .frame(width: radius * 2, height: radius * 2)
                        .rotationEffect(.degrees(spinAngle))
                } else {
                    Circle()
                        .trim(from: 0, to: max(0.02, fraction))
                        .stroke(
                            Color.accentColor,
                            style: StrokeStyle(lineWidth: 10, lineCap: .round)
                        )
                        .frame(width: radius * 2, height: radius * 2)
                        .rotationEffect(.degrees(-90))
                }

                Circle()
                    .fill(Color(white: 0.15))
                    .frame(width: chartSide * 0.24, height: chartSide * 0.24)

                VStack(spacing: 6) {
                    Text(title)
                        .font(.headline)
                        .foregroundStyle(.white)

                    if !isIndeterminate {
                        Text("\(Int(fraction * 100))%")
                            .font(.title3.weight(.semibold).monospacedDigit())
                            .foregroundStyle(.white.opacity(0.9))
                    }

                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.65))
                        .lineLimit(2)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: chartSide * 0.5)
                }
            }
            .frame(width: chartSide, height: chartSide)
        }
        .onAppear {
            guard isIndeterminate else { return }
            withAnimation(.linear(duration: 1.1).repeatForever(autoreverses: false)) {
                spinAngle = 360
            }
        }
    }
}
