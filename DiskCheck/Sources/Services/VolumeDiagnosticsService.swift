import Foundation

enum VolumeDiagnosticsService {
    static func loadReport(for volumeURL: URL) async -> VolumeHealthReport {
        let mountPath = volumeURL.standardizedFileURL.path
        async let diskInfo = diskInfoPlist(for: mountPath)
        async let snapshotInfo = timeMachineSnapshotInfo(for: mountPath)

        let info = await diskInfo
        let snapshots = await snapshotInfo

        return VolumeHealthReport(
            volumeName: info.volumeName ?? volumeURL.lastPathComponent,
            mountPath: mountPath,
            fileSystem: info.fileSystem,
            isEncrypted: info.isEncrypted,
            smartStatus: info.smartStatus,
            timeMachineSnapshotCount: snapshots.count,
            timeMachineSnapshotBytes: snapshots.totalBytes
        )
    }

    private struct DiskInfo {
        var volumeName: String?
        var fileSystem: String?
        var isEncrypted = false
        var smartStatus: DiskSmartStatus = .unknown
    }

    private struct SnapshotInfo {
        var count = 0
        var totalBytes: Int64?
    }

    private static func diskInfoPlist(for mountPath: String) async -> DiskInfo {
        guard let plist = await runPlistCommand(arguments: ["info", "-plist", mountPath]) else {
            return DiskInfo()
        }

        var info = DiskInfo()
        info.volumeName = plist["VolumeName"] as? String
        info.fileSystem = plist["FilesystemName"] as? String ?? plist["FileSystem"] as? String
        if let encrypted = plist["Encrypted"] as? Bool {
            info.isEncrypted = encrypted
        } else if let encrypted = plist["Encrypted"] as? String {
            info.isEncrypted = encrypted.lowercased() == "yes"
        }

        if let smart = plist["SMARTStatus"] as? String {
            info.smartStatus = parseSmartStatus(smart)
        }

        return info
    }

    private static func timeMachineSnapshotInfo(for mountPath: String) async -> SnapshotInfo {
        var info = SnapshotInfo()

        let snapshotNames = await runTextCommand(
            executable: "/usr/bin/tmutil",
            arguments: ["listlocalsnapshots", mountPath]
        )?
        .split(separator: "\n")
        .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        .filter { !$0.isEmpty && $0.contains("com.apple.TimeMachine") } ?? []

        info.count = snapshotNames.count

        if let plist = await runPlistCommand(arguments: ["apfs", "listSnapshots", mountPath, "-plist"]),
           let snapshots = plist["Snapshots"] as? [[String: Any]] {
            var total: Int64 = 0
            var hasSize = false
            for snapshot in snapshots {
                if let bytes = snapshot["BytesUsed"] as? Int64 {
                    total += bytes
                    hasSize = true
                } else if let bytes = snapshot["BytesUsed"] as? Int {
                    total += Int64(bytes)
                    hasSize = true
                }
            }
            if hasSize {
                info.totalBytes = total
            } else {
                info.count = max(info.count, snapshots.count)
            }
        }

        return info
    }

    private static func parseSmartStatus(_ raw: String) -> DiskSmartStatus {
        let normalized = raw.lowercased()
        if normalized.contains("fail") || normalized.contains("error") {
            return .failing
        }
        if normalized.contains("verified") || normalized.contains("normal") {
            return .verified
        }
        if normalized.contains("not supported") || normalized.contains("not available") {
            return .notSupported
        }
        return .unknown
    }

    private static func runPlistCommand(arguments: [String]) async -> [String: Any]? {
        guard let text = await runTextCommand(executable: "/usr/sbin/diskutil", arguments: arguments),
              let data = text.data(using: .utf8),
              let plist = try? PropertyListSerialization.propertyList(
                from: data,
                options: [],
                format: nil
              ) as? [String: Any]
        else { return nil }
        return plist
    }

    private static func runTextCommand(executable: String, arguments: [String]) async -> String? {
        await Task.detached(priority: .utility) {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: executable)
            process.arguments = arguments

            let pipe = Pipe()
            process.standardOutput = pipe
            process.standardError = Pipe()

            do {
                try process.run()
            } catch {
                return nil
            }

            process.waitUntilExit()
            guard process.terminationStatus == 0 else { return nil }

            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            let output = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
            return output?.isEmpty == false ? output : nil
        }.value
    }
}
