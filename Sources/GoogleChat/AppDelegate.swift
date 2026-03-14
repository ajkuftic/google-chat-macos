import AppKit
import Combine

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {

    // MARK: - Dependencies

    /// Strong reference required — ARC will release NSStatusItem if stored weakly or locally.
    private var statusBarController: StatusBarController?
    private var cancellables = Set<AnyCancellable>()
    private let appState = AppState.shared

    // MARK: - NSApplicationDelegate

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.activate(ignoringOtherApps: true)
        statusBarController = StatusBarController(appState: appState)

        // Single source of truth: AppState.unreadCount drives the Dock badge.
        appState.$unreadCount
            .receive(on: DispatchQueue.main)
            .sink { [weak self] count in
                NSApp.dockTile.badgeLabel = count > 0 ? "\(count)" : nil
                self?.statusBarController?.updateBadge(count: count)
            }
            .store(in: &cancellables)
    }

    /// Re-open window when user clicks the Dock icon with no visible windows.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag {
            NSApp.windows.first?.makeKeyAndOrderFront(nil)
        }
        return true
    }

    /// Hide to menu bar instead of terminating when last window is closed.
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return false
    }
}
