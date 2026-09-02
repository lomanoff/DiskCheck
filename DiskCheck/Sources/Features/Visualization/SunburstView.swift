import SwiftUI

struct SunburstView: View {
    let node: DiskNode
    var trashStore: TrashStore
    var isInteractive: Bool = true
    var centerCaption: String? = nil
    var onSelect: (DiskNode) -> Void
    var onCenterTap: () -> Void
    var onStage: (DiskNode) -> Void

    @State private var hoveredSegment: SunburstSegment?

    private let ringGap: CGFloat = 1.5

    private var displayNode: DiskNode {
        DiskNodeTrashCache.filteredForLegend(node, trashedPaths: trashStore.trashedPaths)
    }

    private var segments: [SunburstSegment] {
        DiskNodeTrashCache.sunburstSegments(for: node, trashedPaths: trashStore.trashedPaths)
    }

    private var centerDisplaySize: Int64 {
        isInteractive ? displayNode.size : node.size
    }

    var body: some View {
        Group {
            if isInteractive {
                GeometryReader { geometry in
                    let chartSide = LayoutMetrics.chartSide(
                        width: geometry.size.width,
                        height: geometry.size.height
                    )
                    chartBody(chartSide: chartSide, containerWidth: geometry.size.width)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                }
                .aspectRatio(1, contentMode: .fit)
                .frame(maxWidth: .infinity)
                .frame(maxHeight: LayoutMetrics.maxChartDimension)
            } else {
                StableChartContainer { chartSide in
                    chartBody(chartSide: chartSide, containerWidth: chartSide)
                }
            }
        }
    }

    @ViewBuilder
    private func chartBody(chartSide: CGFloat, containerWidth: CGFloat) -> some View {
        let centerRadius = chartSide * 0.12
        let ringWidth = (chartSide / 2 - centerRadius - 8) / CGFloat(SunburstLayout.maxDepth)
        let center = CGPoint(x: containerWidth / 2, y: chartSide / 2)

        ZStack {
            Canvas(rendersAsynchronously: true) { context, canvasSize in
                let c = CGPoint(x: canvasSize.width / 2, y: canvasSize.height / 2)

                for segment in segments where segment.depth > 0 {
                    let innerR = centerRadius + CGFloat(segment.depth - 1) * ringWidth + ringGap
                    let outerR = centerRadius + CGFloat(segment.depth) * ringWidth - ringGap
                    guard outerR > innerR else { continue }

                    var path = Path()
                    path.addArc(
                        center: c,
                        radius: outerR,
                        startAngle: .radians(segment.startAngle - .pi / 2),
                        endAngle: .radians(segment.endAngle - .pi / 2),
                        clockwise: false
                    )
                    path.addArc(
                        center: c,
                        radius: innerR,
                        startAngle: .radians(segment.endAngle - .pi / 2),
                        endAngle: .radians(segment.startAngle - .pi / 2),
                        clockwise: true
                    )
                    path.closeSubpath()

                    let isTrashed = DiskNodeTrash.isTrashed(segment.node, trashedPaths: trashStore.trashedPaths)
                    let isHovered = hoveredSegment?.id == segment.id

                    if isTrashed {
                        context.fill(path, with: .color(.white.opacity(0.12)))
                        context.stroke(
                            path,
                            with: .color(.white.opacity(0.35)),
                            style: StrokeStyle(lineWidth: 1, dash: [4, 3])
                        )
                    } else {
                        let color = ColorPalette.sunburstColor(for: segment.node, depth: segment.depth - 1)
                        context.fill(path, with: .color(isHovered ? color.opacity(1) : color))
                        context.stroke(path, with: .color(.black.opacity(0.35)), lineWidth: 0.5)
                    }
                }
            }
            .frame(width: chartSide, height: chartSide)
            .id(segmentRenderKey)

            Circle()
                .fill(Color(white: 0.15))
                .frame(width: centerRadius * 2, height: centerRadius * 2)
                .overlay {
                    VStack(spacing: 4) {
                        Text(ByteFormatter.format(centerDisplaySize))
                            .font(.system(size: centerRadius * 0.35, weight: .semibold, design: .rounded))
                            .foregroundStyle(.white)
                            .minimumScaleFactor(0.5)
                            .lineLimit(1)
                            .animation(nil, value: centerDisplaySize)

                        if let hovered = hoveredSegment {
                            Text(hovered.node.name)
                                .font(.caption2)
                                .foregroundStyle(.white.opacity(0.7))
                                .lineLimit(1)
                        } else if let centerCaption, !centerCaption.isEmpty {
                            Text(centerCaption)
                                .font(.caption2)
                                .foregroundStyle(.white.opacity(0.7))
                                .lineLimit(2)
                                .multilineTextAlignment(.center)
                                .animation(nil, value: centerCaption)
                        }
                    }
                    .padding(8)
                }
                .onTapGesture {
                    if isInteractive { onCenterTap() }
                }

            if isInteractive, let hovered = hoveredSegment, hovered.depth > 0 {
                let innerR = centerRadius + CGFloat(hovered.depth - 1) * ringWidth
                let outerR = centerRadius + CGFloat(hovered.depth) * ringWidth
                SunburstSegmentShape(
                    startAngle: hovered.startAngle,
                    endAngle: hovered.endAngle,
                    innerRadius: innerR,
                    outerRadius: outerR
                )
                .stroke(.white.opacity(0.6), lineWidth: 2)
                .frame(width: chartSide, height: chartSide)
                .allowsHitTesting(false)
            }
        }
        .frame(width: containerWidth, height: chartSide, alignment: .top)
        .contentShape(Rectangle())
        .modifier(SunburstInteractionModifier(
            isInteractive: isInteractive,
            dragGesture: dragGesture(center: center, centerRadius: centerRadius, ringWidth: ringWidth),
            hoveredSegment: hoveredSegment,
            trashStore: trashStore,
            onStage: onStage
        ))
        .onContinuousHover { phase in
            guard isInteractive else { return }
            switch phase {
            case .active(let location):
                hoveredSegment = hitTest(
                    at: location,
                    center: center,
                    centerRadius: centerRadius,
                    ringWidth: ringWidth
                )
            case .ended:
                break
            }
        }
    }

    private func dragGesture(
        center: CGPoint,
        centerRadius: CGFloat,
        ringWidth: CGFloat
    ) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                hoveredSegment = hitTest(
                    at: value.location,
                    center: center,
                    centerRadius: centerRadius,
                    ringWidth: ringWidth
                )
            }
            .onEnded { value in
                if let hit = hitTest(
                    at: value.location,
                    center: center,
                    centerRadius: centerRadius,
                    ringWidth: ringWidth
                ) {
                    if DiskNodeTrash.isTrashed(hit.node, trashedPaths: trashStore.trashedPaths) {
                        // Не проваливаемся в помеченные элементы
                    } else {
                        onSelect(hit.node)
                    }
                }
                hoveredSegment = nil
            }
    }

    private var segmentRenderKey: String {
        let childSignature = displayNode.sortedChildren.map {
            "\($0.id.uuidString):\($0.size):\($0.children.count)"
        }.joined(separator: "|")
        return "\(displayNode.size)|\(childSignature)|\(trashStore.trashedPathsRevision)"
    }

    private func hitTest(
        at point: CGPoint,
        center: CGPoint,
        centerRadius: CGFloat,
        ringWidth: CGFloat
    ) -> SunburstSegment? {
        SunburstLayout.hitTest(
            segments: segments,
            point: point,
            center: center,
            innerRadius: centerRadius,
            ringWidth: ringWidth
        )
    }
}

private struct SunburstInteractionModifier<G: Gesture>: ViewModifier {
    let isInteractive: Bool
    let dragGesture: G
    let hoveredSegment: SunburstSegment?
    let trashStore: TrashStore
    let onStage: (DiskNode) -> Void

    func body(content: Content) -> some View {
        if isInteractive {
            content
                .gesture(dragGesture)
                .contextMenu {
                    if let hovered = hoveredSegment {
                        Button("Показать в Finder", systemImage: "folder") {
                            FinderReveal.show(hovered.node)
                        }
                        if !DiskNodeTrash.isTrashed(hovered.node, trashedPaths: trashStore.trashedPaths) {
                            Button("В корзину", systemImage: "trash") {
                                onStage(hovered.node)
                            }
                        }
                    }
                }
        } else {
            content
        }
    }
}

struct SunburstSegmentShape: Shape {
    let startAngle: Double
    let endAngle: Double
    let innerRadius: CGFloat
    let outerRadius: CGFloat

    func path(in rect: CGRect) -> Path {
        let center = CGPoint(x: rect.midX, y: rect.midY)
        var path = Path()
        path.addArc(
            center: center,
            radius: outerRadius,
            startAngle: .radians(startAngle - .pi / 2),
            endAngle: .radians(endAngle - .pi / 2),
            clockwise: false
        )
        path.addArc(
            center: center,
            radius: innerRadius,
            startAngle: .radians(endAngle - .pi / 2),
            endAngle: .radians(startAngle - .pi / 2),
            clockwise: true
        )
        path.closeSubpath()
        return path
    }
}
