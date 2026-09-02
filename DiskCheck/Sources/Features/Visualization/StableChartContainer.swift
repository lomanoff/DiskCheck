import SwiftUI

/// Фиксирует высоту квадратного графика по ширине колонки, чтобы соседняя панель
/// не сдвигала его по вертикали при изменении своей высоты.
struct StableChartContainer<Content: View>: View {
    @ViewBuilder var content: (CGFloat) -> Content

    @State private var chartSide = LayoutMetrics.minChartDimension

    var body: some View {
        content(chartSide)
            .frame(maxWidth: .infinity)
            .frame(height: chartSide, alignment: .top)
            .background {
                GeometryReader { geometry in
                    Color.clear
                        .onAppear {
                            updateChartSide(for: geometry.size.width)
                        }
                        .onChange(of: geometry.size.width) { _, width in
                            updateChartSide(for: width)
                        }
                }
            }
    }

    private func updateChartSide(for width: CGFloat) {
        let nextSide = LayoutMetrics.chartSide(forWidth: width)
        guard abs(nextSide - chartSide) > 0.5 else { return }
        chartSide = nextSide
    }
}
