/* Optional script installed by the destination owner, not injected by HUB.
 * <script src="https://YOUR-HUB/workspace-navigation-bridge.js"
 *         data-hub-origin="https://YOUR-HUB" defer></script>
 * No credentials, page contents, or URLs are sent to HUB.
 */
(function () {
  'use strict';
  var script = document.currentScript;
  var origin;
  try {
    var raw = script && script.getAttribute('data-hub-origin');
    var parsed = new URL(raw);
    if (parsed.protocol !== 'https:' || parsed.origin !== raw) return;
    origin = parsed.origin;
  } catch (_) { return; }
  if (window.parent === window || window.__hubWorkspaceNavigation) return;
  window.__hubWorkspaceNavigation = true;
  var channel = 'hub.workspace.navigation.v1';
  var nonce = '';
  var nav = window.navigation;
  function state() {
    if (!nonce) return;
    window.parent.postMessage({ channel: channel, type: 'state', nonce: nonce,
      supported: !!nav, back: !!(nav && nav.canGoBack), forward: !!(nav && nav.canGoForward)
    }, origin);
  }
  window.addEventListener('message', function (event) {
    var data = event.data;
    if (event.source !== window.parent || event.origin !== origin || !data ||
        data.channel !== channel || typeof data.nonce !== 'string' || data.nonce.length > 128) return;
    if (data.type === 'hello') { nonce = data.nonce; state(); return; }
    if (data.nonce !== nonce || data.type !== 'navigate' || !nav) return;
    var navigation;
    if (data.direction === 'back' && nav.canGoBack) navigation = nav.back();
    else if (data.direction === 'forward' && nav.canGoForward) navigation = nav.forward();
    if (navigation && navigation.finished) navigation.finished.then(state, state);
  });
  if (nav) {
    nav.addEventListener('currententrychange', state);
    nav.addEventListener('navigatesuccess', state);
    nav.addEventListener('navigateerror', state);
  }
}());
