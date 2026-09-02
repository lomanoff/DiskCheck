import Foundation

enum SecurityScopedAccess {
    @discardableResult
    static func begin(url: URL) -> Bool {
        if url.startAccessingSecurityScopedResource() {
            return true
        }
        return url.path.hasPrefix(NSHomeDirectory())
    }

    static func end(url: URL) {
        url.stopAccessingSecurityScopedResource()
    }
}
