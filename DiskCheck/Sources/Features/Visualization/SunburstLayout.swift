import Foundation
import CoreGraphics

struct SunburstSegment: Identifiable, Equatable {
    let id: UUID
    let node: DiskNode
    let startAngle: Double
    let endAngle: Double
    let depth: Int

    init(node: DiskNode, startAngle: Double, endAngle: Double, depth: Int) {
        self.id = node.id
        self.node = node
        self.startAngle = startAngle
        self.endAngle = endAngle
        self.depth = depth
    }
}

enum SunburstLayout {
    static let maxDepth = 5

    static func segments(for root: DiskNode, maxRingDepth: Int = maxDepth) -> [SunburstSegment] {
        var result: [SunburstSegment] = []
        layout(
            node: root,
            startAngle: 0,
            endAngle: 2 * .pi,
            depth: 0,
            maxDepth: maxRingDepth,
            segments: &result
        )
        return result
    }

    private static func layout(
        node: DiskNode,
        startAngle: Double,
        endAngle: Double,
        depth: Int,
        maxDepth: Int,
        segments: inout [SunburstSegment]
    ) {
        segments.append(SunburstSegment(
            node: node,
            startAngle: startAngle,
            endAngle: endAngle,
            depth: depth
        ))

        guard depth < maxDepth, !node.children.isEmpty else { return }

        let children = node.sortedChildren
        let total = children.reduce(Int64(0)) { $0 + max($1.size, 1) }
        guard total > 0 else { return }

        var current = startAngle
        let span = endAngle - startAngle

        for child in children {
            let fraction = Double(max(child.size, 1)) / Double(total)
            let childEnd = current + span * fraction
            layout(
                node: child,
                startAngle: current,
                endAngle: childEnd,
                depth: depth + 1,
                maxDepth: maxDepth,
                segments: &segments
            )
            current = childEnd
        }
    }

    static func hitTest(
        segments: [SunburstSegment],
        point: CGPoint,
        center: CGPoint,
        innerRadius: CGFloat,
        ringWidth: CGFloat
    ) -> SunburstSegment? {
        let dx = point.x - center.x
        let dy = point.y - center.y
        let distance = sqrt(dx * dx + dy * dy)
        let depth = Int((distance - innerRadius) / ringWidth)

        guard depth >= 0 else { return nil }

        var angle = atan2(dy, dx) + .pi / 2
        if angle < 0 { angle += 2 * .pi }

        let targetDepth = depth + 1
        var best: SunburstSegment?

        for segment in segments where segment.depth == targetDepth {
            guard angle >= segment.startAngle, angle <= segment.endAngle else { continue }
            if let current = best {
                if segment.node.size > current.node.size {
                    best = segment
                }
            } else {
                best = segment
            }
        }

        return best
    }
}
