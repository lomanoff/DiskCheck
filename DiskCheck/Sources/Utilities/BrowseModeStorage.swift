import Foundation

enum BrowseModeStorage {
    private static let key = "browseMode"

    static func load() -> BrowseMode {
        guard let raw = UserDefaults.standard.string(forKey: key),
              let mode = BrowseMode(rawValue: raw)
        else {
            return .categories
        }
        return mode
    }

    static func save(_ mode: BrowseMode) {
        UserDefaults.standard.set(mode.rawValue, forKey: key)
    }
}
