/**
 * bridge.js — Google Chat ↔ macOS native bridge
 *
 * Security controls:
 * - Nonce: every postToNative call includes a per-launch nonce embedded at injection time.
 *   Third-party scripts on chat.google.com cannot read this nonce (it's a closure variable).
 * - Conditional clone: response.clone() only called when URL matches chat API pattern (P1-03).
 * - Silent catch replaced with error counter for observability.
 * - sendReply receives typed arguments from callAsyncJavaScript — no string interpolation (P1-01).
 *
 * Injected by WKUserScript at document end, main frame only.
 * '__BRIDGE_NONCE_PLACEHOLDER__' is replaced with the actual nonce by Swift before injection.
 */
(function (NONCE) {
  'use strict';

  // ── Utility ──────────────────────────────────────────────────────────────

  function postToNative(type, payload) {
    try {
      window.webkit.messageHandlers.chatBridge.postMessage(
        Object.assign({ type: type, nonce: NONCE }, payload)
      );
    } catch (e) {
      // Handler may not be registered yet (e.g. during page transition).
      console.warn('[bridge] postToNative failed:', e.message);
    }
  }

  // ── Bridge Ready ──────────────────────────────────────────────────────────

  postToNative('bridgeReady', {});

  // ── Unread Count — document title observer ─────────────────────────────────
  //
  // Google Chat encodes the unread count in the document title: "(3) Google Chat"
  // MutationObserver on <title> is the lightest-weight approach — zero API interception.

  function readUnreadFromTitle() {
    var match = document.title.match(/\((\d+)\)/);
    return match ? parseInt(match[1], 10) : 0;
  }

  var titleEl = document.querySelector('title');
  if (titleEl) {
    var titleObserver = new MutationObserver(function () {
      postToNative('unreadCount', { count: readUnreadFromTitle() });
    });
    titleObserver.observe(titleEl, { childList: true });
    // Post immediately with the current value.
    postToNative('unreadCount', { count: readUnreadFromTitle() });
  }

  // ── New Message Detection — fetch intercept ───────────────────────────────
  //
  // Phase 1 spike: intercepts fetch responses from chat API endpoints.
  // ⚠️  Validate during spike that:
  //   (a) Google Chat's CSP does not block this injection
  //   (b) The URL pattern and response shape are correct
  // Fallback if CSP blocks: remove this section and rely on MutationObserver on message nodes.

  var origFetch = window.fetch;
  window.fetch = function () {
    var args = Array.prototype.slice.call(arguments);
    return origFetch.apply(this, args).then(function (response) {
      var url = typeof args[0] === 'string' ? args[0] : (args[0] && args[0].url) || '';

      // P1-03 FIX: clone ONLY when URL matches — never for unrelated requests.
      if (url.indexOf('chat/v1') !== -1) {
        var clone = response.clone();
        clone.text().then(function (body) {
          try {
            var data = JSON.parse(body);
            if (data && Array.isArray(data.messages)) {
              data.messages.forEach(function (msg) {
                // Truncate fields before crossing the bridge to limit payload size.
                postToNative('newMessage', {
                  sender:    String(msg.sender && msg.sender.name || 'Someone').slice(0, 150),
                  space:     String(msg.space && msg.space.displayName || '').slice(0, 150),
                  text:      String(msg.text || '').slice(0, 500),
                  threadId:  String(msg.thread && msg.thread.name || '').slice(0, 200),
                  spaceId:   String(msg.space && msg.space.name || '').slice(0, 200),
                  messageId: String(msg.name || Date.now()).slice(0, 200)
                });
              });
            }
          } catch (_) {
            // Report parse failures as an observable signal rather than silently swallowing.
            postToNative('parseError', { count: 1 });
          }
        });
      }

      return response;
    });
  };

  // ── Reply Injection — called via callAsyncJavaScript from Swift ────────────
  //
  // Swift calls: webView.callAsyncJavaScript(
  //   "return window.__gcBridge.sendReply(text, threadId, spaceId)",
  //   arguments: ["text": ..., "threadId": ..., "spaceId": ...]
  // )
  //
  // Arguments are JSON-encoded by WebKit — no string interpolation, no injection surface.
  // Implementation is a stub for Phase 1. Full implementation validated during spike
  // once the compose box DOM structure is understood.

  window.__gcBridge = {
    sendReply: function (text, threadId, spaceId) {
      // TODO (Phase 3): Locate the compose box for the given threadId/spaceId,
      // set its value, and dispatch a submit event.
      // Return a promise that resolves on success and rejects on failure.
      //
      // Spike checklist item: Can evaluateJavaScript interact with the compose box?
      console.log('[bridge] sendReply stub called — threadId:', threadId, 'text:', text.slice(0, 50));
      return Promise.resolve();
    }
  };

}('__BRIDGE_NONCE_PLACEHOLDER__'));
