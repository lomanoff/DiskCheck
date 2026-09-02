import XCTest
@testable import DiskCheck

final class ScanInodeRegistryTests: XCTestCase {
    func testCreditsSameInodeOnlyOnce() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("DiskCheckInodeTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        let original = directory.appendingPathComponent("original.bin")
        let linked = directory.appendingPathComponent("linked.bin")
        let data = Data(repeating: 0xAB, count: 4096)
        try data.write(to: original)
        try FileManager.default.linkItem(at: original, to: linked)

        let registry = ScanInodeRegistry()
        let first = registry.creditedSize(at: original)
        let second = registry.creditedSize(at: linked)

        XCTAssertGreaterThan(first, 0)
        XCTAssertEqual(second, 0)
        XCTAssertEqual(registry.uniqueTotalBytes, first)
    }
}
