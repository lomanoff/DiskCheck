import CoreGraphics
import Foundation

enum SidebarWidthStorage {
    private static let key = "sidebarWidth"
    static let defaultWidth: CGFloat = 300
    static let minimumWidth: CGFloat = 240

    static func load() -> CGFloat {
        let stored = UserDefaults.standard.double(forKey: key)
        guard stored >= Double(minimumWidth) else { return defaultWidth }
        return CGFloat(stored)
    }

    static func save(_ width: CGFloat) {
        guard width >= minimumWidth else { return }
        UserDefaults.standard.set(Double(width), forKey: key)
    }
}
