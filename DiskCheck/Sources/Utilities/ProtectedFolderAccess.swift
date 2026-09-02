import Foundation

/// Прогревает доступ к стандартным папкам пользователя, чтобы macOS показала TCC-диалоги
/// (Desktop, Documents, …) у sandbox-приложения без FDA.
enum ProtectedFolderAccess {
    private static let relativePaths = [
        "Desktop",
        "Documents",
        "Downloads",
        "Music",
        "Pictures",
        "Movies",
    ]

    static func warmUpForVolumeScan(at scanURL: URL) {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        guard scanURL.path == "/System/Volumes/Data" || scanURL.path.hasPrefix(home) else {
            return
        }

        for relativePath in relativePaths {
            let path = (home as NSString).appendingPathComponent(relativePath)
            requestAccessIfNeeded(at: path)
        }

        requestAccessIfNeeded(at: home + "/Library")
    }

    private static func requestAccessIfNeeded(at path: String) {
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory),
              isDirectory.boolValue
        else { return }

        _ = try? FileManager.default.contentsOfDirectory(atPath: path)
    }
}
