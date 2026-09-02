import Foundation

/// Учитывает каждый inode на диске один раз, чтобы hard link и общие файлы
/// между Applications, Library и другими папками не раздували итог.
final class ScanInodeRegistry: @unchecked Sendable {
    private let lock = NSLock()
    private var seenInodes = Set<Data>()
    private var uniqueBytes: Int64 = 0

    private let sizeKeys: Set<URLResourceKey> = [
        .fileResourceIdentifierKey,
        .totalFileAllocatedSizeKey,
        .fileSizeKey,
    ]

    func creditedSize(at url: URL, values: URLResourceValues? = nil) -> Int64 {
        let resolved = values ?? (try? url.resourceValues(forKeys: sizeKeys))
        let logicalSize = logicalByteSize(from: resolved)
        guard logicalSize > 0 else { return 0 }

        guard let identifier = inodeData(from: resolved?.fileResourceIdentifier) else {
            recordUnique(logicalSize)
            return logicalSize
        }

        lock.lock()
        if seenInodes.contains(identifier) {
            lock.unlock()
            return 0
        }
        seenInodes.insert(identifier)
        uniqueBytes += logicalSize
        lock.unlock()
        return logicalSize
    }

    var uniqueTotalBytes: Int64 {
        lock.lock()
        defer { lock.unlock() }
        return uniqueBytes
    }

    private func logicalByteSize(from values: URLResourceValues?) -> Int64 {
        if let allocated = values?.totalFileAllocatedSize {
            return Int64(allocated)
        }
        if let size = values?.fileSize {
            return Int64(size)
        }
        return 0
    }

    private func recordUnique(_ size: Int64) {
        lock.lock()
        uniqueBytes += size
        lock.unlock()
    }

    private func inodeData(from identifier: (any NSCopying & NSSecureCoding)?) -> Data? {
        if let data = identifier as? Data {
            return data
        }
        if let data = identifier as? NSData {
            return data as Data
        }
        return nil
    }
}
