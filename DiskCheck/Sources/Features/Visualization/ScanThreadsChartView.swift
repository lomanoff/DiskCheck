import SwiftUI

struct ScanThreadsChartView: View {
    let activity: ScanActivitySnapshot

    private let timelineWindow: TimeInterval = 18
    private let bucketCount = 36

    var body: some View {
        concurrencyTimeline
    }

    private var concurrencyTimeline: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Text("Параллельность")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)

                Spacer()

                Text("за \(Int(timelineWindow)) с")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }

            TimelineView(.animation(minimumInterval: 0.35)) { timeline in
                let buckets = concurrencyBuckets(at: timeline.date)
                let peak = max(buckets.max() ?? 0, 1)

                Canvas { context, size in
                    drawConcurrencyHeatmap(
                        in: &context,
                        size: size,
                        buckets: buckets,
                        peak: peak
                    )
                }
                .frame(height: 28)
                .background(Color.primary.opacity(0.03), in: RoundedRectangle(cornerRadius: 8))
            }
        }
    }

    private func drawConcurrencyHeatmap(
        in context: inout GraphicsContext,
        size: CGSize,
        buckets: [Int],
        peak: Int
    ) {
        let inset: CGFloat = 4
        let barHeight = size.height - inset * 2
        let bucketWidth = (size.width - inset * 2) / CGFloat(bucketCount)

        for index in 0..<bucketCount {
            let count = buckets[index]
            let fraction = CGFloat(count) / CGFloat(peak)
            let x = inset + CGFloat(index) * bucketWidth
            let filledHeight = max(2, barHeight * fraction)
            let rect = CGRect(
                x: x,
                y: inset + (barHeight - filledHeight),
                width: max(1, bucketWidth - 1),
                height: filledHeight
            )

            let color: Color
            if count == 0 {
                color = .primary.opacity(0.05)
            } else {
                let lane = min(count - 1, ColorPalette.branchColors.count - 1)
                color = ColorPalette.branchColors[lane].opacity(0.35 + fraction * 0.55)
            }

            context.fill(
                Path(roundedRect: rect, cornerRadius: 2),
                with: .color(color)
            )
        }
    }

    private func concurrencyBuckets(at now: Date) -> [Int] {
        let windowStart = now.addingTimeInterval(-timelineWindow)
        let bucketDuration = timelineWindow / Double(bucketCount)
        let intervals = activeIntervals(now: now, windowStart: windowStart)

        return (0..<bucketCount).map { index in
            let bucketStart = windowStart + bucketDuration * Double(index)
            let bucketEnd = bucketStart + bucketDuration
            let overlapCount = intervals.filter { interval in
                interval.end > bucketStart && interval.start < bucketEnd
            }.count
            return overlapCount
        }
    }

    private func activeIntervals(now: Date, windowStart: Date) -> [DateInterval] {
        let activeIDs = Set(activity.activeWorkers.map(\.id))
        var openStarts: [UInt64: Date] = [:]
        var intervals: [DateInterval] = []

        for event in activity.recentEvents where event.timestamp >= windowStart {
            switch event.event {
            case .started:
                if !activeIDs.contains(event.id) {
                    openStarts[event.id] = event.timestamp
                }
            case .finished:
                let start = openStarts.removeValue(forKey: event.id) ?? windowStart
                let clampedStart = max(start, windowStart)
                if event.timestamp > clampedStart {
                    intervals.append(DateInterval(start: clampedStart, end: event.timestamp))
                }
            }
        }

        for worker in activity.activeWorkers {
            let start = max(worker.startedAt, windowStart)
            if now > start {
                intervals.append(DateInterval(start: start, end: now))
            }
        }

        return intervals
    }
}
