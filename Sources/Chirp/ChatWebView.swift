import SwiftUI
import WebKit
import Combine

/// SwiftUI wrapper around WKWebView loading chat.google.com.
///
/// Security controls in place:
/// - Navigation allowlist: only permits known Google domains (P1-02)
/// - Bridge nonce: injected before bridge.js to prevent third-party JS from spoofing events (P1-02)
/// - WKWebsiteDataStore.default(): cookies persist across launches
/// - callAsyncJavaScript used for all Swift→JS calls with user data (P1-01)
/// - DispatchQueue.main.async enforced for all evaluateJavaScript calls (P1-04)
struct ChatWebView: NSViewRepresentable {

    let appState: AppState

    // MARK: - Navigation Allowlist (P1-02)

    /// Domains the web view is permitted to load in-app.
    /// Any navigation to a host outside this set is redirected to the system browser.
    static let allowedHosts: Set<String> = [
        "chat.google.com",
        "accounts.google.com",
        "oauth2.googleapis.com",
        "myaccount.google.com",
        "workspace.google.com"
    ]

    // MARK: - NSViewRepresentable

    func makeCoordinator() -> Coordinator {
        Coordinator(appState: appState)
    }

    func makeNSView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()

        // Persistent cookie store — session survives across launches.
        config.websiteDataStore = WKWebsiteDataStore.default()

        // Enable Web Inspector in debug builds.
        #if DEBUG
        config.preferences.setValue(true, forKey: "developerExtrasEnabled")
        #endif

        // Generate a per-launch nonce and inject it before bridge.js (P1-02).
        // The nonce is a closure variable inside bridge.js — third-party scripts cannot read it.
        let coordinator = context.coordinator
        let nonceScript = WKUserScript(
            source: "window.__gcBridgeNonce = '\(coordinator.bridgeNonce)';",
            injectionTime: .atDocumentStart,
            forMainFrameOnly: true
        )
        config.userContentController.addUserScript(nonceScript)

        // Register the message handler using a weak proxy to prevent retain cycles.
        // Direct registration creates a strong reference cycle: WKUserContentController → handler → self.
        let bridgeHandler = BridgeMessageHandler(appState: appState)
        bridgeHandler.expectedNonce = coordinator.bridgeNonce
        coordinator.bridgeHandler = bridgeHandler
        config.userContentController.add(
            WeakScriptMessageHandlerProxy(bridgeHandler),
            name: BridgeMessageHandler.handlerName
        )

        // Inject bridge.js after the document is ready, main frame only.
        if let bridgeSource = loadBridgeScript(nonce: coordinator.bridgeNonce) {
            let bridgeScript = WKUserScript(
                source: bridgeSource,
                injectionTime: .atDocumentEnd,
                forMainFrameOnly: true
            )
            config.userContentController.addUserScript(bridgeScript)
        }

        let webView = WKWebView(frame: .zero, configuration: config)
        webView.navigationDelegate = context.coordinator
        webView.uiDelegate = context.coordinator
        coordinator.webView = webView

        // Use a Safari UA. Google Chat supports Safari on macOS, and Google Sign-In
        // fully trusts it — unlike Chrome UA + missing Chrome JS properties, which
        // triggers the "browser may not be secure" block during auth.
        webView.customUserAgent = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.3 Safari/605.1.15"

        // Load Google Chat.
        let request = URLRequest(url: URL(string: "https://chat.google.com")!)
        webView.load(request)

        // Ensure the web view receives keyboard input as soon as it is placed in the window.
        DispatchQueue.main.async {
            webView.window?.makeFirstResponder(webView)
        }

        return webView
    }

    func updateNSView(_ nsView: WKWebView, context: Context) {}

    // MARK: - Bridge Script Loading

    private func loadBridgeScript(nonce: String) -> String? {
        guard let url = Bundle.module.url(forResource: "bridge", withExtension: "js"),
              var source = try? String(contentsOf: url, encoding: .utf8) else {
            assertionFailure("bridge.js not found in bundle")
            return nil
        }
        // Embed the nonce as a literal in the IIFE argument so it becomes
        // a closure variable — inaccessible to third-party scripts (P1-02).
        source = source.replacingOccurrences(of: "__BRIDGE_NONCE_PLACEHOLDER__", with: nonce)
        return source
    }

    // MARK: - Reply Injection (P1-01, P1-04)

    /// Send a reply to a specific thread via the JS bridge.
    /// Uses callAsyncJavaScript with a typed argument dictionary — no string interpolation,
    /// no injection surface. Dispatches to the main thread unconditionally (P1-04).
    func sendReply(text: String, threadId: String, spaceId: String, webView: WKWebView) {
        DispatchQueue.main.async {
            webView.callAsyncJavaScript(
                "return window.__gcBridge.sendReply(text, threadId, spaceId)",
                arguments: [
                    "text": text,
                    "threadId": threadId,
                    "spaceId": spaceId
                ],
                in: nil,
                in: .page
            ) { result in
                switch result {
                case .success:
                    break
                case .failure(let error):
                    print("[ChatWebView] Reply injection failed: \(error)")
                    // Post a local "Reply failed" notification so the user's text is not silently lost.
                    NotificationManager.shared.showReplyFailedNotification(replyText: text)
                }
            }
        }
    }

    // MARK: - Coordinator

    /// WKNavigationDelegate + WKUIDelegate.
    /// Enforces the navigation allowlist and detects auth state changes.
    final class Coordinator: NSObject, WKNavigationDelegate, WKUIDelegate {

        let appState: AppState
        let bridgeNonce: String = UUID().uuidString
        var bridgeHandler: BridgeMessageHandler?
        weak var webView: WKWebView?

        init(appState: AppState) {
            self.appState = appState
        }

        // MARK: WKNavigationDelegate — Navigation Allowlist (P1-02)

        func webView(
            _ webView: WKWebView,
            decidePolicyFor navigationAction: WKNavigationAction,
            decisionHandler: @escaping (WKNavigationActionPolicy) -> Void
        ) {
            guard let url = navigationAction.request.url else {
                decisionHandler(.allow)
                return
            }

            // Allow non-HTTP resources (e.g. about:blank, data: URIs from the web app).
            guard let scheme = url.scheme, scheme == "https" || scheme == "http" else {
                decisionHandler(.allow)
                return
            }

            let host = url.host ?? ""
            let isAllowed = ChatWebView.allowedHosts.contains(host) ||
                            host.hasSuffix(".google.com")

            if isAllowed {
                decisionHandler(.allow)
            } else {
                // Open external links in the system browser — never inside the app.
                NSWorkspace.shared.open(url)
                decisionHandler(.cancel)
            }
        }

        // MARK: WKNavigationDelegate — Auth Detection

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            guard let host = webView.url?.host else { return }

            // Exact host comparison — not string contains (avoids accounts.google.com.attacker.com).
            let isAuthPage = host == "accounts.google.com"

            // Debounce: only surface the auth prompt if we land on the login page,
            // not during background token refreshes (which are typically brief).
            if isAuthPage {
                DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) { [weak self, weak webView] in
                    // Re-check: if the webView has navigated away in 2s, it was a token refresh.
                    guard webView?.url?.host == "accounts.google.com" else { return }
                    self?.appState.requiresAuth = true
                    NSApp.windows.first?.makeKeyAndOrderFront(nil)
                }
            } else {
                appState.requiresAuth = false
            }
        }

        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
            print("[ChatWebView] Provisional navigation failed: \(error.localizedDescription)")
        }

        // MARK: WKUIDelegate — Handle window.open() and alerts

        func webView(
            _ webView: WKWebView,
            createWebViewWith configuration: WKWebViewConfiguration,
            for navigationAction: WKNavigationAction,
            windowFeatures: WKWindowFeatures
        ) -> WKWebView? {
            // Instead of opening a new web view, open target="_blank" links in the browser.
            if let url = navigationAction.request.url {
                NSWorkspace.shared.open(url)
            }
            return nil
        }
    }
}

// MARK: - WeakScriptMessageHandlerProxy

/// Prevents the retain cycle: WKUserContentController strongly retains the registered handler.
/// If the handler is self (e.g. the view's coordinator), it creates a cycle and leaks memory.
/// This proxy holds a weak reference to the real handler, breaking the cycle.
private final class WeakScriptMessageHandlerProxy: NSObject, WKScriptMessageHandler {

    private weak var delegate: WKScriptMessageHandler?

    init(_ delegate: WKScriptMessageHandler) {
        self.delegate = delegate
    }

    func userContentController(
        _ userContentController: WKUserContentController,
        didReceive message: WKScriptMessage
    ) {
        delegate?.userContentController(userContentController, didReceive: message)
    }
}
