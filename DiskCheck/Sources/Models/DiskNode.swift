import Foundation

struct DiskNode: Identifiable, Sendable, Hashable {
    let id: UUID
    let url: URL
    let name: String
    var size: Int64
    var children: [DiskNode]
    let isDirectory: Bool
    var colorIndex: Int
    var needsLazyScan: Bool

    init(
        id: UUID = UUID(),
        url: URL,
        name: String,
        size: Int64 = 0,
        children: [DiskNode] = [],
        isDirectory: Bool = true,
        colorIndex: Int = 0,
        needsLazyScan: Bool = false
    ) {
        self.id = id
        self.url = url
        self.name = name
        self.size = size
        self.children = children
        self.isDirectory = isDirectory
        self.colorIndex = colorIndex
        self.needsLazyScan = needsLazyScan
    }

    var sortedChildren: [DiskNode] {
        children.sorted { $0.size > $1.size }
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }

    static func == (lhs: DiskNode, rhs: DiskNode) -> Bool {
        lhs.id == rhs.id
    }
}

struct DiskScanResult: Sendable {
    let root: DiskNode
    let totalCapacity: Int64
    let availableSpace: Int64
    let scannedAt: Date
}

struct VolumeInfo: Sendable, Identifiable, Hashable {
    let id: String
    let name: String
    let url: URL
    let totalCapacity: Int64
    let availableSpace: Int64
}
