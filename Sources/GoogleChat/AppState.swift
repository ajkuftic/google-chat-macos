import Foundation
import Combine

/// Central observable state. Passed as a dependency — avoid accessing AppState.shared
/// outside of the composition root (GoogleChatApp / AppDelegate).
@MainActor
final class AppState: ObservableObject {

    // MARK: - Shared instance (composition root only)
    static let shared = AppState()

    // MARK: - Published state

    /// Current unread message count across all spaces.
    /// Single source of truth: drives both the Dock badge and the menu bar badge.
    @Published var unreadCount: Int = 0

    /// True when the macOS Focus filter has requested notification suppression.
    @Published var notificationsSuppressed: Bool = false

    /// True when the web view has navigated to the Google auth page mid-session.
    @Published var requiresAuth: Bool = false

    // MARK: - Init

    private init() {}
}
