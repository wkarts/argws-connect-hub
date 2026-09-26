// Persist only application identities. Never store URLs, passwords, tokens or
// foreign-page data; restore only after the server reauthorizes the catalog.
export const WORKSPACE_SESSION_VERSION = 1;
const PREFIX = 'hub:workspace:session:v1:';
const MAX_TABS = 100;
const validId = value => Number.isSafeInteger(value) && value > 0;
const storageKey = scope => /^\d+:\d+$/.test(scope || '') ? `${PREFIX}${scope}` : null;

export const readWorkspaceSession = (storage, scope) => {
  try {
    const key = storageKey(scope);
    if (!key) return null;
    const raw = storage.getItem(key);
    if (!raw || raw.length > 20000) return null;
    const data = JSON.parse(raw);
    if (data.version !== WORKSPACE_SESSION_VERSION || !Array.isArray(data.tabs)) return null;
    const seen = new Set();
    const tabs = data.tabs.slice(0, MAX_TABS).filter(tab => {
      if (!tab || !validId(tab.id) || typeof tab.revision !== 'string' || !/^[a-f0-9]{64}$/.test(tab.revision) || seen.has(tab.id)) return false;
      seen.add(tab.id);
      return true;
    }).map(tab => ({ id: tab.id, revision: tab.revision }));
    return { tabs, activeId: seen.has(data.activeId) ? data.activeId : null };
  } catch (_) { return null; }
};

export const writeWorkspaceSession = (storage, state) => {
  try {
    const key = storageKey(state.scope);
    if (!key || !state.sessionRestored) return;
    storage.setItem(key, JSON.stringify({
      version: WORKSPACE_SESSION_VERSION,
      tabs: state.tabs.slice(0, MAX_TABS).map(tab => ({ id: tab.id, revision: tab.app.integration_revision })),
      activeId: state.activeId,
    }));
  } catch (_) { /* Storage can be disabled or full; running tabs still work. */ }
};

export const restoredApplications = (snapshot, catalog) => {
  const available = new Map(catalog.filter(app => app.enabled && app.launch_mode === 'embedded').map(app => [app.id, app]));
  return (snapshot?.tabs || []).flatMap(tab => {
    const app = available.get(tab.id);
    return app && app.integration_revision === tab.revision ? [app] : [];
  });
};
