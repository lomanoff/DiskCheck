import Foundation

enum FullDiskAccessStorage {
    private static let skipPromptKey = "fullDiskAccessPromptSkipped"
    private static let userConfirmedKey = "fullDiskAccessUserConfirmed"
    private static let storageVersionKey = "fullDiskAccessStorageVersion"
    private static let currentStorageVersion = 2

    static var hasSkippedPrompt: Bool {
        UserDefaults.standard.bool(forKey: skipPromptKey)
    }

    static var userConfirmedGranted: Bool {
        UserDefaults.standard.bool(forKey: userConfirmedKey)
    }

    static func setSkippedPrompt(_ skipped: Bool) {
        UserDefaults.standard.set(skipped, forKey: skipPromptKey)
    }

    static func setUserConfirmedGranted(_ confirmed: Bool) {
        UserDefaults.standard.set(confirmed, forKey: userConfirmedKey)
    }

    static func clearAssumptions() {
        UserDefaults.standard.removeObject(forKey: skipPromptKey)
        UserDefaults.standard.removeObject(forKey: userConfirmedKey)
    }

    /// Сбрасывает устаревшие флаги после исправления логики FDA (v2).
    static func migrateIfNeeded() {
        let version = UserDefaults.standard.integer(forKey: storageVersionKey)
        guard version < currentStorageVersion else { return }
        clearAssumptions()
        UserDefaults.standard.set(currentStorageVersion, forKey: storageVersionKey)
    }
}
