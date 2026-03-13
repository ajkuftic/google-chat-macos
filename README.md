# Google Chat for macOS

A native macOS app wrapper for Google Chat with menu bar presence, Dock badge, and OS notifications.

## Features

- **Menu bar icon** with unread message badge
- **Dock badge** showing unread count
- **Native OS notifications** for new messages
- **Persistent session** — stay logged in across launches
- **External link handling** — links open in your default browser
- **Focus mode integration** *(Phase 4)*

## Requirements

- macOS 14 Sonoma or later
- Google account with Chat access

## Building

Open `Package.swift` in Xcode 16+ or build via command line:

```bash
swift build -c release
```

### Code Signing

Before building for distribution, configure signing in Xcode:

1. Open `Package.swift` in Xcode
2. Select the `GoogleChat` target
3. Set your Team and Bundle Identifier under Signing & Capabilities
4. Add `GoogleChatApp.entitlements` as the entitlements file

## Architecture

The app embeds `chat.google.com` in a `WKWebView` and bridges native macOS features via a JavaScript↔Swift message bridge.

```
GoogleChatApp          @main entry point
AppDelegate            NSApplicationDelegate, Dock badge, window lifecycle
AppState               @MainActor ObservableObject, shared reactive state
ChatWebView            WKWebView wrapper, bridge injection, navigation allowlist
BridgeMessageHandler   WKScriptMessageHandler, nonce validation, event routing
StatusBarController    NSStatusItem, unread badge
NotificationManager    UNUserNotificationCenter, notifications
bridge.js              JS-side bridge: fetch intercept, title observer, reply stub
```

### Security Controls

- **Bridge nonce** — per-launch UUID embedded as a closure variable in `bridge.js`; prevents third-party scripts on `chat.google.com` from spoofing bridge events
- **Navigation allowlist** — only Google domains load in-app; all other links open in the system browser
- **Typed JS→Swift calls** — `callAsyncJavaScript(arguments:)` with a typed dictionary; no string interpolation
- **Main-thread enforcement** — all WebView calls dispatched to `DispatchQueue.main`
- **App Sandbox** — entitlements grant only outbound network access

## Implementation Phases

| Phase | Status | Description |
|-------|--------|-------------|
| 1 — Spike | ✅ Done | WKWebView shell, JS bridge, menu bar, basic notifications |
| 2 — Polish | 🔲 Planned | Full StatusBar, AppDelegate, auth UX |
| 3 — Notifications | 🔲 Planned | Inline reply, burst coalescing, Focus suppression |
| 4 — Focus Filter | 🔲 Planned | `SetFocusFilterIntent`, AppIntents |
| 5 — Distribution | 🔲 Planned | Notarization, DMG packaging |

## License

MIT
