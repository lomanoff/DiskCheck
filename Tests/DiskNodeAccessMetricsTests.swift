import XCTest
@testable import DiskCheck

final class DiskNodeAccessMetricsTests: XCTestCase {
    func testDetectsInaccessibleDirectories() {
        let root = DiskNode(
            url: URL(fileURLWithPath: "/tmp/root"),
            name: "Root",
            size: 10_000,
            children: [
                DiskNode(
                    url: URL(fileURLWithPath: "/tmp/root/🔒 Library"),
                    name: "🔒 Library",
                    size: 6_000,
                    children: [
                        DiskNode(
                            url: URL(fileURLWithPath: "/tmp/root/🔒 Library/hidden"),
                            name: "🔒 Содержимое",
                            size: 2_000,
                            isDirectory: false
                        ),
                    ]
                ),
                DiskNode(
                    url: URL(fileURLWithPath: "/tmp/root/Users"),
                    name: "Users",
                    size: 4_000
                ),
            ]
        )

        XCTAssertEqual(DiskNodeAccessMetrics.inaccessibleSize(in: root), 8_000)
        XCTAssertEqual(DiskNodeAccessMetrics.inaccessibleDirectoryCount(in: root), 1)
    }
}
