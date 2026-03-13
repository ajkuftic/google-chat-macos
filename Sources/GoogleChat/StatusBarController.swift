import AppKit
import Combine

/// Manages the persistent menu bar icon with unread badge.
///
/// NSStatusItem must be held with a strong reference — ARC will deallocate it
/// immediately if stored weakly or as a local variable, removing the icon.
final class StatusBarController {

    // MARK: - Dependencies

    private let appState: AppState
    private var cancellables = Set<AnyCancellable>()

    // MARK: - Status Bar

    private var statusItem: NSStatusItem!

    // MARK: - Init

    init(appState: AppState) {
        self.appState = appState
        setupStatusItem()
        observeAppState()
    }

    // MARK: - Setup

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)

        if let button = statusItem.button {
            button.image = baseImage()
            button.image?.isTemplate = true  // Automatically adapts to Dark Mode
            button.toolTip = "Google Chat"
        }

        statusItem.menu = buildMenu()
    }

    private func observeAppState() {
        // Badge updates are debounced: rapid count changes (e.g. marking many messages read)
        // coalesce into a single redraw within 100ms.
        appState.$unreadCount
            .debounce(for: .milliseconds(100), scheduler: DispatchQueue.main)
            .sink { [weak self] count in self?.updateBadge(count: count) }
            .store(in: &cancellables)
    }

    // MARK: - Badge

    func updateBadge(count: Int) {
        guard let button = statusItem.button else { return }

        if count <= 0 {
            button.image = baseImage()
            button.image?.isTemplate = true
            return
        }

        // Draw a custom badge: the base icon with a red circle and count string overlaid.
        let size = NSSize(width: 18, height: 18)
        let badgedImage = NSImage(size: size, flipped: false) { rect in
            // Draw base icon
            if let base = NSImage(systemSymbolName: "message.fill", accessibilityDescription: nil) {
                base.draw(in: NSRect(x: 1, y: 1, width: 13, height: 13))
            }

            // Draw red badge circle
            NSColor.systemRed.setFill()
            let badgeRect = NSRect(x: 9, y: 9, width: 9, height: 9)
            NSBezierPath(ovalIn: badgeRect).fill()

            // Draw count text
            let label = count > 99 ? "99+" : "\(count)"
            let attrs: [NSAttributedString.Key: Any] = [
                .foregroundColor: NSColor.white,
                .font: NSFont.systemFont(ofSize: 6, weight: .bold)
            ]
            let str = NSAttributedString(string: label, attributes: attrs)
            let textSize = str.size()
            let textOrigin = NSPoint(
                x: badgeRect.midX - textSize.width / 2,
                y: badgeRect.midY - textSize.height / 2
            )
            str.draw(at: textOrigin)
            return true
        }

        badgedImage.isTemplate = false
        button.image = badgedImage
    }

    // MARK: - Menu

    private func buildMenu() -> NSMenu {
        let menu = NSMenu()
        menu.addItem(withTitle: "Show Google Chat", action: #selector(showWindow), keyEquivalent: "")
            .target = self
        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit Google Chat", action: #selector(quit), keyEquivalent: "q")
            .target = self
        return menu
    }

    @objc private func showWindow() {
        NSApp.activate(ignoringOtherApps: true)
        NSApp.windows.first?.makeKeyAndOrderFront(nil)
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }

    // MARK: - Helpers

    private func baseImage() -> NSImage? {
        NSImage(systemSymbolName: "message.fill", accessibilityDescription: "Google Chat")
    }
}
