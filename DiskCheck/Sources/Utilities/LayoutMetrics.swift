import AppKit
import CoreGraphics

enum LayoutMetrics {
    static let minChartDimension: CGFloat = 220

    static var maxChartDimension: CGFloat {
        visibleScreenLength * 0.5
    }

    private static var visibleScreenLength: CGFloat {
        if let screen = NSScreen.main?.visibleFrame {
            return min(screen.width, screen.height)
        }
        return 900
    }

    static func chartSide(width: CGFloat, height: CGFloat) -> CGFloat {
        let proposed = min(width, height, maxChartDimension)
        return max(minChartDimension, proposed)
    }

    /// Стабильный размер графика: зависит только от ширины колонки, не от высоты.
    static func chartSide(forWidth width: CGFloat) -> CGFloat {
        let proposed = min(width, maxChartDimension)
        return max(minChartDimension, proposed)
    }
}
