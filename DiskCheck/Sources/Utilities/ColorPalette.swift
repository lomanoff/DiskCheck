import SwiftUI

enum ColorPalette {
    static let branchColors: [Color] = [
        Color(red: 0.45, green: 0.82, blue: 0.35), // зелёный — Users
        Color(red: 0.35, green: 0.65, blue: 0.95), // синий — System
        Color(red: 0.70, green: 0.55, blue: 0.95), // фиолетовый — Library
        Color(red: 0.95, green: 0.45, blue: 0.65), // розовый — Applications
        Color(red: 0.95, green: 0.75, blue: 0.30), // жёлтый
        Color(red: 0.50, green: 0.85, blue: 0.80), // бирюзовый
        Color(red: 0.85, green: 0.55, blue: 0.40), // оранжевый
        Color(red: 0.60, green: 0.60, blue: 0.65), // серый
    ]

    static let fileSegmentColor = Color(red: 0.48, green: 0.48, blue: 0.52)

    static func color(for node: DiskNode, depth: Int = 0) -> Color {
        let base = branchColors[node.colorIndex % branchColors.count]
        let factor = 1.0 - Double(depth) * 0.08
        return base.opacity(max(0.55, factor))
    }

    /// Цвет сегмента на sunburst: файлы — сплошной серый, папки — цвет ветки.
    static func sunburstColor(for node: DiskNode, depth: Int = 0) -> Color {
        guard node.isDirectory else { return fileSegmentColor }
        return color(for: node, depth: depth)
    }

    static func colorIndex(for position: Int) -> Int {
        position % branchColors.count
    }
}
