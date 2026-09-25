export const NAVIGATION_CHANNEL = 'hub.workspace.navigation.v1';

// Opt-in bridge only. A foreign iframe's history must never be replaced with
// window.history.back(), which could navigate away from the HUB itself.
export function navigationMessage(event, frame, origin, nonce) {
  const data = event.data;
  return typeof nonce === 'string' && nonce.length > 0 && !!frame && event.source === frame.contentWindow && event.origin === origin &&
    !!data && data.channel === NAVIGATION_CHANNEL && data.nonce === nonce &&
    data.type === 'state' && typeof data.supported === 'boolean' &&
    typeof data.back === 'boolean' && typeof data.forward === 'boolean';
}

export function navigationNonce() {
  const bytes = new Uint32Array(4);
  window.crypto.getRandomValues(bytes);
  return Array.from(bytes, value => value.toString(16)).join('-');
}
