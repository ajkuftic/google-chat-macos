import SwiftUI
import AppKit

@main
struct GoogleChatApp: App {

    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(AppState.shared)
        }
        .windowStyle(.titleBar)
        .windowToolbarStyle(.unified)
        .commands {
            // Remove File > New Window — single-window app
            CommandGroup(replacing: .newItem) {}
        }
    }
}
