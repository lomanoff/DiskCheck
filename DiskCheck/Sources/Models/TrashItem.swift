import Foundation

struct TrashItem: Identifiable, Equatable, Sendable {
    let id: UUID
    let url: URL
    let name: String
    let size: Int64
    let isDirectory: Bool
    let addedAt: Date

    init(
        id: UUID = UUID(),
        url: URL,
        name: String,
        size: Int64,
        isDirectory: Bool,
        addedAt: Date = .now
    ) {
        self.id = id
        self.url = url
        self.name = name
        self.size = size
        self.isDirectory = isDirectory
        self.addedAt = addedAt
    }

    var path: String { url.path }
}
