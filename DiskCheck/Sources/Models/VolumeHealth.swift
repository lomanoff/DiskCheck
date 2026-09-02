import Foundation

enum DiskSmartStatus: String, Sendable {
    case verified
    case failing
    case notSupported
    case unknown

    var isHealthy: Bool {
        switch self {
        case .verified, .notSupported: true
        case .failing, .unknown: false
        }
    }

    var title: String {
        switch self {
        case .verified: "SMART: в норме"
        case .failing: "SMART: ошибка диска"
        case .notSupported: "SMART: не поддерживается"
        case .unknown: "SMART: неизвестно"
        }
    }
}

struct VolumeHealthReport: Sendable {
    let volumeName: String
    let mountPath: String
    let fileSystem: String?
    let isEncrypted: Bool
    let smartStatus: DiskSmartStatus
    let timeMachineSnapshotCount: Int
    let timeMachineSnapshotBytes: Int64?

    var hasUnhealthySmart: Bool {
        smartStatus == .failing
    }

    var hasTimeMachineSnapshots: Bool {
        timeMachineSnapshotCount > 0 || (timeMachineSnapshotBytes ?? 0) > 0
    }
}

struct ICloudStorageSummary: Sendable {
    let nosyncSize: Int64
    let nosyncCount: Int
    let mobileDocumentsSize: Int64
    let mobileDocumentsCount: Int
    let iCloudDriveSize: Int64
    let locallyStoredSize: Int64
    let cloudOnlySize: Int64

    var totalTrackedSize: Int64 {
        max(mobileDocumentsSize, nosyncSize + iCloudDriveSize)
    }

    var hasContent: Bool {
        nosyncCount > 0 || mobileDocumentsCount > 0 || locallyStoredSize > 0 || cloudOnlySize > 0
    }
}
