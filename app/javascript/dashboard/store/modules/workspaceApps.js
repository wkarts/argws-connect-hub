import api from 'dashboard/api/workspaceApps';
import { reconcileWorkspaceTabs, safeApplicationUrl, workspaceScope } from 'dashboard/helper/workspaceApps.mjs';

export const createState = () => ({
  scope: '', epoch: 0, accountId: null, apps: [], tabs: [], activeId: null,
  launcherOpen: false, loading: false, failed: false, requestId: 0, openRequestId: 0, sequence: 0,
});

export const mutations = {
  reset(state, { accountId, userId } = {}) {
    const scope = workspaceScope(accountId, userId);
    if (state.scope === scope) return;
    Object.assign(state, createState(), { scope, epoch: state.epoch + 1, accountId: Number(accountId) || null });
  },
  loading(state) { state.loading = true; state.failed = false; state.requestId += 1; },
  failed(state) { state.loading = false; state.failed = true; },
  catalog(state, apps) {
    state.apps = apps;
    state.tabs = reconcileWorkspaceTabs(state.tabs, apps);
    if (!state.tabs.some(tab => tab.id === state.activeId)) state.activeId = null;
    state.loading = false;
    state.failed = false;
  },
  launcher(state, value) { state.launcherOpen = value; },
  deactivate(state) { state.activeId = null; state.launcherOpen = false; state.openRequestId += 1; },
  opening(state) { state.openRequestId += 1; state.launcherOpen = false; },
  open(state, app) {
    const previous = state.tabs.find(tab => tab.id === app.id);
    if (previous && previous.app.integration_revision !== app.integration_revision) {
      state.tabs = state.tabs.filter(tab => tab.id !== app.id);
    }
    if (!state.tabs.some(tab => tab.id === app.id)) {
      state.sequence += 1;
      state.tabs.push({ id: app.id, key: `${state.scope}:${app.id}:${state.sequence}`, app });
    }
    state.activeId = app.id;
  },
  close(state, id) {
    state.tabs = state.tabs.filter(tab => tab.id !== id);
    if (state.activeId === id) state.activeId = state.tabs.length ? state.tabs[state.tabs.length - 1].id : null;
    state.openRequestId += 1;
  },
  reload(state, id) {
    const tab = state.tabs.find(item => item.id === id);
    if (!tab) return;
    state.sequence += 1;
    tab.key = `${state.scope}:${id}:${state.sequence}`;
  },
};

export const actions = {
  async refresh({ state, commit }) {
    if (!state.scope) return;
    const scope = state.scope;
    const epoch = state.epoch;
    commit('loading');
    const requestId = state.requestId;
    try {
      const { data } = await api.list(state.accountId);
      if (state.scope !== scope || state.epoch !== epoch || state.requestId !== requestId) return;
      commit('catalog', data.filter(app => safeApplicationUrl(app.url, window.location.origin)));
    } catch (error) {
      if (state.scope !== scope || state.epoch !== epoch || state.requestId !== requestId) return;
      if ([401, 403].includes(error.response?.status)) commit('catalog', []);
      // An offline interval does not destroy active frames or restart their sessions.
      commit('failed');
    }
  },
  async open({ state, commit }, id) {
    const scope = state.scope;
    if (!scope) return;
    const epoch = state.epoch;
    commit('opening');
    const existing = state.tabs.find(tab => tab.id === Number(id));
    if (existing) { commit('open', existing.app); return; }
    const requestId = state.openRequestId;
    const { data: app } = await api.show(state.accountId, id);
    if (state.scope !== scope || epoch !== state.epoch || requestId !== state.openRequestId) return;
    if (app.launch_mode !== 'embedded' || !safeApplicationUrl(app.url, window.location.origin)) throw new Error('application_unavailable');
    commit('open', app);
  },
};

export default { namespaced: true, state: createState(), mutations, actions };
