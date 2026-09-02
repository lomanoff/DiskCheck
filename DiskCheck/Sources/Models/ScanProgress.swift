import Foundation

enum ScanPhase: String, Sendable {
    case estimating
    case scanning
}

struct ScanProgress: Sendable {
    let currentItem: String
    let completed: Int
    let total: Int
    let phase: ScanPhase
    let isComplete: Bool
    let discoveredBytes: Int64?
    let volumeUsedTarget: Int64?

    init(
        currentItem: String,
        completed: Int,
        total: Int,
        phase: ScanPhase,
        isComplete: Bool = false,
        discoveredBytes: Int64? = nil,
        volumeUsedTarget: Int64? = nil
    ) {
        self.currentItem = currentItem
        self.completed = completed
        self.total = total
        self.phase = phase
        self.isComplete = isComplete
        self.discoveredBytes = discoveredBytes
        self.volumeUsedTarget = volumeUsedTarget
    }

    var fraction: Double {
        if isComplete { return 1.0 }

        if let discoveredBytes, let volumeUsedTarget, volumeUsedTarget > 0 {
            return min(0.99, Double(discoveredBytes) / Double(volumeUsedTarget))
        }

        guard total > 0 else { return 0 }
        let raw = Double(completed) / Double(total)
        return min(0.97, raw)
    }
}
