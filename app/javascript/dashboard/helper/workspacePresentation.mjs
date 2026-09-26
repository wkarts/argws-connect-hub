// Reuse the native HUB tooltip directive/style; never attach hints to the iframe.
export const workspaceTooltip = (content, rtl = false) => ({
  content, placement: rtl ? 'left' : 'right', container: 'body',
  // Popper must use the viewport, not the 64 px scroll parent of either app rail.
  // Appending to body alone does not change its default overflow boundary.
  boundariesElement: 'viewport', offset: 8, html: false,
  delay: { show: 180, hide: 0 }, trigger: 'hover focus',
  classes: ['workspace-tooltip'], autoHide: true,
});

export function toolbarPreference(scope, value) {
  if (!scope) return false;
  try {
    const key = `hub:workspace:toolbar:${scope}`;
    if (typeof value === 'boolean') localStorage.setItem(key, value ? '1' : '0');
    return localStorage.getItem(key) === '1';
  } catch (_) { return typeof value === 'boolean' ? value : false; }
}

export function menuPosition(x, y, width, height) {
  return {
    left: `${Math.max(8, Math.min(Number(x) || 8, width - 232))}px`,
    top: `${Math.max(8, Math.min(Number(y) || 8, height - 210))}px`,
  };
}

export function safeDiagnosticUrl(value) {
  try { const url = new URL(value); return `${url.origin}${url.pathname}`; }
  catch (_) { return ''; }
}
