import WebKit
import Combine

/// Receives and routes events posted by bridge.js via window.webkit.messageHandlers.chatBridge.
///
/// Security: validates a per-launch nonce on every message to prevent third-party scripts
/// on chat.google.com from spoofing bridge events (P1-02).
final class BridgeMessageHandler: NSObject, WKScriptMessageHandler {

    // MARK: - Constants

    static let handlerName = "chatBridge"

    // MARK: - Dependencies

    private let appState: AppState

    /// The nonce embedded in bridge.js at injection time. Every bridge message must include it.
    var expectedNonce: String = ""

    // MARK: - Deduplication

    /// Rolling set of recently-seen messageIds. Prevents duplicate notifications from
    /// API response refetches delivering the same messages multiple times.
    /// 500-item cap (generous for burst scenarios; ~30 KB of strings at most).
    private var seenMessageIds: [String] = []
    private var seenMessageIdSet: Set<String> = []
    private let deduplicationCap = 500

    // MARK: - Init

    init(appState: AppState) {
        self.appState = appState
        super.init()
    }

    // MARK: - WKScriptMessageHandler

    func userContentController(
        _ userContentController: WKUserContentController,
        didReceive message: WKScriptMessage
    ) {
        guard let body = message.body as? [String: Any] else {
            print("[Bridge] Received non-dictionary message — ignored")
            return
        }

        // Nonce validation (P1-02): reject messages from third-party scripts.
        guard let nonce = body["nonce"] as? String, nonce == expectedNonce else {
            print("[Bridge] Nonce mismatch — message rejected")
            return
        }

        guard let type = body["type"] as? String else {
            print("[Bridge] Missing type field — ignored")
            return
        }

        switch type {
        case "bridgeReady":
            handleBridgeReady()

        case "unreadCount":
            guard let count = body["count"] as? Int else { return }
            handleUnreadCount(count)

        case "newMessage":
            guard
                let sender = body["sender"] as? String,
                let space = body["space"] as? String,
                let text = body["text"] as? String,
                let threadId = body["threadId"] as? String,
                let spaceId = body["spaceId"] as? String,
                let messageId = body["messageId"] as? String
            else {
                print("[Bridge] newMessage event missing required fields")
                return
            }
            // Field length validation: clamp attacker-controlled strings (P1-02).
            handleNewMessage(
                sender: String(sender.prefix(150)),
                space: String(space.prefix(150)),
                text: String(text.prefix(500)),
                threadId: String(threadId.prefix(200)),
                spaceId: String(spaceId.prefix(200)),
                messageId: String(messageId.prefix(200))
            )

        case "parseError":
            // bridge.js encountered an unexpected API response shape.
            let count = body["count"] as? Int ?? 1
            print("[Bridge] JS parse error count: \(count) — Google may have changed API shape")

        default:
            print("[Bridge] Unknown event type: \(type)")
        }
    }

    // MARK: - Event Handlers

    private func handleBridgeReady() {
        print("[Bridge] ✅ bridge.js loaded and connected")
    }

    private func handleUnreadCount(_ count: Int) {
        Task { @MainActor in
            appState.unreadCount = count
        }
    }

    private func handleNewMessage(
        sender: String,
        space: String,
        text: String,
        threadId: String,
        spaceId: String,
        messageId: String
    ) {
        // Deduplication: skip messages we've already processed.
        guard !seenMessageIdSet.contains(messageId) else { return }
        insertSeen(messageId)

        print("[Bridge] New message from \(sender) in \(space): \(text.prefix(50))...")

        // For Phase 1 spike: just log. NotificationManager wired in Phase 3.
        NotificationManager.shared.showNotification(
            sender: sender,
            space: space,
            text: text,
            threadId: threadId,
            spaceId: spaceId,
            messageId: messageId,
            appState: appState
        )
    }

    // MARK: - Deduplication Helpers

    private func insertSeen(_ id: String) {
        if seenMessageIds.count >= deduplicationCap {
            let evicted = seenMessageIds.removeFirst()
            seenMessageIdSet.remove(evicted)
        }
        seenMessageIds.append(id)
        seenMessageIdSet.insert(id)
    }
}
