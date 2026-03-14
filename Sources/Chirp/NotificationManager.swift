import UserNotifications
import AppKit

/// Phase 1: Minimal stub. Full implementation in Phase 3.
///
/// Currently only prints to console and shows macOS notifications.
/// Inline reply, Focus filter suppression, and burst coalescing added in Phase 3.
final class NotificationManager: NSObject {

    static let shared = NotificationManager()

    private override init() {
        super.init()
        UNUserNotificationCenter.current().delegate = self
    }

    // MARK: - Authorization

    /// Request notification permission after the first successful Google Chat load.
    /// Never called before auth — avoids the permission dialog before the user sees the app.
    func requestAuthorization() {
        UNUserNotificationCenter.current().requestAuthorization(
            options: [.alert, .sound, .badge]
        ) { granted, error in
            if let error { print("[Notifications] Auth error: \(error)") }
            print("[Notifications] Permission granted: \(granted)")
        }
    }

    // MARK: - Show Notification (Phase 1: basic)

    func showNotification(
        sender: String,
        space: String,
        text: String,
        threadId: String,
        spaceId: String,
        messageId: String,
        appState: AppState
    ) {
        // Phase 3: check appState.notificationsSuppressed here.
        // Phase 3: burst coalescing here.

        let content = UNMutableNotificationContent()
        content.title = "\(sender) in \(space)"
        // Privacy-preserving default: show generic body until opt-in implemented in Phase 3.
        // Avoids persisting message PII to the OS notification database by default.
        content.body = "New message"
        content.userInfo = [
            "threadId": threadId,
            "spaceId": spaceId,
            "messageId": messageId
        ]
        content.threadIdentifier = spaceId  // Groups notifications by space

        let request = UNNotificationRequest(
            identifier: messageId,
            content: content,
            trigger: nil
        )
        UNUserNotificationCenter.current().add(request) { error in
            if let error { print("[Notifications] Failed to post: \(error)") }
        }
    }

    // MARK: - Reply Failed

    func showReplyFailedNotification(replyText: String) {
        let content = UNMutableNotificationContent()
        content.title = "Reply not sent"
        content.body = "Open Chirp to send your reply."
        // NOTE: Never include replyText in the notification body — it would be persisted
        // to the OS notification database outside the app's control.

        let request = UNNotificationRequest(
            identifier: "reply-failed-\(UUID())",
            content: content,
            trigger: nil
        )
        UNUserNotificationCenter.current().add(request) { error in
            if let error { print("[Notifications] Failed to post reply-failed: \(error)") }
        }
    }
}

// MARK: - UNUserNotificationCenterDelegate

extension NotificationManager: UNUserNotificationCenterDelegate {

    /// Show notifications even when the app is in the foreground.
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound])
    }

    /// Handle notification tap: bring window to front.
    /// Phase 3: add REPLY_ACTION and MARK_READ_ACTION handling here.
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        // Default action (tap): bring the window to front.
        NSApp.activate(ignoringOtherApps: true)
        NSApp.windows.first?.makeKeyAndOrderFront(nil)

        // Phase 3: route to the specific conversation using threadId/spaceId from userInfo.

        completionHandler()
    }
}
