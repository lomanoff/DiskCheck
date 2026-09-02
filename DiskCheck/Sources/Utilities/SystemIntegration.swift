import AppKit
import Foundation

enum SystemIntegration {
    static func openDiskUtility() {
        let candidates = [
            "/System/Applications/Utilities/Disk Utility.app",
            "/Applications/Utilities/Disk Utility.app",
        ]
        for path in candidates {
            let url = URL(fileURLWithPath: path)
            if FileManager.default.fileExists(atPath: path) {
                NSWorkspace.shared.open(url)
                return
            }
        }
    }

    static func openTimeMachineSettings() {
        let candidates = [
            "x-apple.systempreferences:com.apple.Time-Machine-Settings.extension",
            "x-apple.systempreferences:com.apple.preference.security?TimeMachine",
        ]
        for candidate in candidates {
            if let url = URL(string: candidate) {
                NSWorkspace.shared.open(url)
                return
            }
        }
        openStorageSettings()
    }

    static func openStorageSettings() {
        let candidates = [
            "x-apple.systempreferences:com.apple.settings.Storage",
            "x-apple.systempreferences:com.apple.preference.storage",
        ]
        for candidate in candidates {
            if let url = URL(string: candidate) {
                NSWorkspace.shared.open(url)
                return
            }
        }
    }

    static func openTimeMachineSnapshotsHelp() {
        if let url = URL(string: "https://support.apple.com/ru-ru/102396") {
            NSWorkspace.shared.open(url)
        }
    }
}
