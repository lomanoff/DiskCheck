import Foundation

enum FullDiskAccessChecker {
    private static var probePaths: [String] {
        let home = NSHomeDirectory()
        return [
            home + "/Desktop",
            home + "/Documents",
            home + "/Downloads",
            home + "/Library",
            home + "/Library/Mail",
            home + "/Library/Safari",
            home + "/Library/Messages",
        ]
    }

    /// Реальная проверка через чтение защищённых папок.
    static var isProbeGranted: Bool {
        let fileManager = FileManager.default
        for path in probePaths {
            if canReadProtectedDirectory(at: path, using: fileManager) {
                return true
            }
        }
        return false
    }

    /// Для UI: probe или пользователь подтвердил FDA (sandbox часто не детектирует probe).
    static var isGranted: Bool {
        isProbeGranted || userAssumesGranted
    }

    /// Пользователь вручную подтвердил, что FDA уже включён.
    static var userAssumesGranted: Bool {
        FullDiskAccessStorage.userConfirmedGranted
    }

    /// Можно пропустить диалог перед сканом.
    static var maySkipPrompt: Bool {
        isGranted || FullDiskAccessStorage.hasSkippedPrompt
    }

    static func refreshAssumptions() {
        if isProbeGranted {
            FullDiskAccessStorage.setUserConfirmedGranted(true)
            FullDiskAccessStorage.setSkippedPrompt(true)
        }
    }

    private static func canReadProtectedDirectory(at path: String, using fileManager: FileManager) -> Bool {
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: path, isDirectory: &isDirectory), isDirectory.boolValue else {
            return false
        }
        return (try? fileManager.contentsOfDirectory(atPath: path)) != nil
    }
}
