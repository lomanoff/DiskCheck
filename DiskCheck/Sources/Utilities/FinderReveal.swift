import AppKit
import Foundation

enum FinderReveal {
    static func show(_ node: DiskNode) {
        let url = node.url.standardizedFileURL
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }
}
