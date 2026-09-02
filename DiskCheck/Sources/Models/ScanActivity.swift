import Foundation

enum ScanWorkerKind: String, Sendable, Equatable {
    case directory
    case enumerate
    case recurse

    var title: String {
        switch self {
        case .directory: "Папка"
        case .enumerate: "Перечисление"
        case .recurse: "Рекурсия"
        }
    }

    var symbolName: String {
        switch self {
        case .directory: "folder"
        case .enumerate: "list.bullet"
        case .recurse: "arrow.triangle.branch"
        }
    }
}

struct ScanWorkerSnapshot: Identifiable, Sendable, Equatable {
    let id: UInt64
    let lane: Int
    let name: String
    let path: String
    let kind: ScanWorkerKind
    let startedAt: Date
}

struct ScanActivityEvent: Identifiable, Sendable, Equatable {
    enum EventKind: Sendable, Equatable {
        case started
        case finished
    }

    let id: UInt64
    let lane: Int
    let name: String
    let kind: ScanWorkerKind
    let timestamp: Date
    let event: EventKind
}

struct ScanActivitySnapshot: Sendable, Equatable {
    let maxLanes: Int
    let activeWorkers: [ScanWorkerSnapshot]
    let recentEvents: [ScanActivityEvent]

    var activeCount: Int { activeWorkers.count }

    static let empty = ScanActivitySnapshot(maxLanes: 1, activeWorkers: [], recentEvents: [])
}

final class ScanActivityTracker: @unchecked Sendable {
    private let maxLanes: Int
    private let onUpdate: (@Sendable (ScanActivitySnapshot) -> Void)?
    private let lock = NSLock()
    private var nextID: UInt64 = 1
    private var availableLanes: [Int]
    private var workers: [UInt64: ScanWorkerSnapshot] = [:]
    private var recentEvents: [ScanActivityEvent] = []
    private let maxRecentEvents = 200
    private let eventRetention: TimeInterval = 22

    init(maxLanes: Int, onUpdate: (@Sendable (ScanActivitySnapshot) -> Void)?) {
        self.maxLanes = max(maxLanes, 1)
        self.onUpdate = onUpdate
        self.availableLanes = Array(0..<self.maxLanes)
    }

    func begin(name: String, path: String, kind: ScanWorkerKind) -> UInt64 {
        lock.lock()
        let id = nextID
        nextID += 1
        let lane: Int
        if let freeLane = availableLanes.first {
            availableLanes.removeFirst()
            lane = freeLane
        } else {
            lane = workers.values.map(\.lane).max().map { $0 + 1 } ?? 0
        }
        let worker = ScanWorkerSnapshot(
            id: id,
            lane: lane,
            name: name,
            path: path,
            kind: kind,
            startedAt: .now
        )
        workers[id] = worker
        appendEventLocked(
            ScanActivityEvent(
                id: id,
                lane: lane,
                name: name,
                kind: kind,
                timestamp: .now,
                event: .started
            )
        )
        lock.unlock()
        publish()
        return id
    }

    func update(id: UInt64, name: String) {
        lock.lock()
        guard var worker = workers[id] else {
            lock.unlock()
            return
        }
        worker = ScanWorkerSnapshot(
            id: worker.id,
            lane: worker.lane,
            name: name,
            path: worker.path,
            kind: worker.kind,
            startedAt: worker.startedAt
        )
        workers[id] = worker
        lock.unlock()
        publish()
    }

    func end(id: UInt64) {
        lock.lock()
        guard let worker = workers.removeValue(forKey: id) else {
            lock.unlock()
            return
        }
        if laneIsReusable(worker.lane) {
            availableLanes.append(worker.lane)
            availableLanes.sort()
        }
        appendEventLocked(
            ScanActivityEvent(
                id: id,
                lane: worker.lane,
                name: worker.name,
                kind: worker.kind,
                timestamp: .now,
                event: .finished
            )
        )
        lock.unlock()
        publish()
    }

    private func laneIsReusable(_ lane: Int) -> Bool {
        lane < maxLanes
    }

    private func appendEventLocked(_ event: ScanActivityEvent) {
        recentEvents.append(event)
        let cutoff = Date().addingTimeInterval(-eventRetention)
        recentEvents.removeAll { $0.timestamp < cutoff }
        if recentEvents.count > maxRecentEvents {
            recentEvents.removeFirst(recentEvents.count - maxRecentEvents)
        }
    }

    private func publish() {
        lock.lock()
        let snapshot = ScanActivitySnapshot(
            maxLanes: maxLanes,
            activeWorkers: workers.values.sorted {
                if $0.lane == $1.lane { return $0.startedAt < $1.startedAt }
                return $0.lane < $1.lane
            },
            recentEvents: recentEvents
        )
        lock.unlock()
        onUpdate?(snapshot)
    }
}
