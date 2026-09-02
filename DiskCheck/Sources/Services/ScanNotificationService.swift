import AppKit
import Foundation
import OSLog
import UserNotifications

enum ScanNotificationService {
    private static let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "DiskCheck", category: "notifications")
    private static let scanCompleteCategoryID = "scan-complete"

    static func requestAuthorizationIfNeeded() {
        Task { @MainActor in
            _ = await ensureAuthorization(requestIfNeeded: true)
        }
    }

    @MainActor
    static func notifyScanCompleted(volumeName: String, totalSize: Int64) async {
        guard await ensureAuthorization(requestIfNeeded: true) else {
            logger.error("Scan-complete notification skipped: authorization not granted")
            showInAppFallback(volumeName: volumeName, totalSize: totalSize)
            return
        }

        let delivered = await deliver(volumeName: volumeName, totalSize: totalSize)
        if !delivered {
            showInAppFallback(volumeName: volumeName, totalSize: totalSize)
        }
    }

    @MainActor
    @discardableResult
    private static func ensureAuthorization(requestIfNeeded: Bool) async -> Bool {
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()

        switch settings.authorizationStatus {
        case .authorized, .provisional, .ephemeral:
            return true
        case .denied:
            logger.error("Notification authorization denied in System Settings")
            return false
        case .notDetermined:
            guard requestIfNeeded else { return false }
            do {
                let granted = try await center.requestAuthorization(options: [.alert, .sound, .badge])
                logger.info("Notification authorization request result: \(granted, privacy: .public)")
                return granted
            } catch {
                logger.error("Notification authorization failed: \(error.localizedDescription, privacy: .public)")
                return false
            }
        @unknown default:
            return false
        }
    }

    @MainActor
    @discardableResult
    private static func deliver(volumeName: String, totalSize: Int64) async -> Bool {
        let content = UNMutableNotificationContent()
        content.title = "Сканирование завершено"
        content.body = "\(volumeName) — \(ByteFormatter.format(totalSize))"
        content.sound = .default
        content.categoryIdentifier = scanCompleteCategoryID

        let request = UNNotificationRequest(
            identifier: "scan-complete-\(UUID().uuidString)",
            content: content,
            trigger: nil
        )

        do {
            try await UNUserNotificationCenter.current().add(request)
            logger.info("Posted scan-complete notification for \(volumeName, privacy: .public)")
            return true
        } catch {
            logger.error("Failed to post scan-complete notification: \(error.localizedDescription, privacy: .public)")
            return false
        }
    }

    @MainActor
    private static func showInAppFallback(volumeName: String, totalSize: Int64) {
        let alert = NSAlert()
        alert.alertStyle = .informational
        alert.messageText = "Сканирование завершено"
        alert.informativeText = "\(volumeName) — \(ByteFormatter.format(totalSize))"
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }
}

final class AppNotificationDelegate: NSObject, NSApplicationDelegate, UNUserNotificationCenterDelegate {
    override init() {
        super.init()
        UNUserNotificationCenter.current().delegate = self
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        UNUserNotificationCenter.current().delegate = self
        ScanNotificationService.requestAuthorizationIfNeeded()
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .sound, .list]
    }
}
