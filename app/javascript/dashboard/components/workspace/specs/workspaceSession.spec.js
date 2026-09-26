import Vue from 'vue';
import Vuex from 'vuex';
import { createLocalVue, mount } from '@vue/test-utils';
import WorkspaceHost from '../WorkspaceHost.vue';
import workspaceModule, { createState } from 'dashboard/store/modules/workspaceApps';
import api from 'dashboard/api/workspaceApps';

vi.mock('dashboard/api/workspaceApps', () => ({ default: { list: vi.fn(), credential: vi.fn() } }));
const localVue = createLocalVue(); localVue.use(Vuex); localVue.directive('tooltip', {});
const application = { id: 1, name: 'Manual', enabled: true, url: 'https://external.example.test/home', icon_name: 'globe', launch_mode: 'embedded', auth_mode: 'session', integration_revision: 'a'.repeat(64) };
const flush = async () => { for (let n = 0; n < 8; n += 1) await Vue.nextTick(); };
let wrapper;
const mountHost = () => {
  const store = new Vuex.Store({ getters: { getCurrentAccountId: () => 1, isLoggedIn: () => true, getCurrentUser: () => ({ id: 1 }), 'accounts/isRTL': () => false }, modules: { workspaceApps: { ...workspaceModule, state: createState() } } });
  wrapper = mount(WorkspaceHost, { localVue, store, attachTo: document.body, stubs: { 'hub-modal': true, 'hub-button': true, 'fluent-icon': true, WorkspaceIcon: true }, mocks: { $t: key => key, $route: Vue.observable({ fullPath: '/app/accounts/1/conversations' }) } });
  return store;
};
beforeEach(() => { localStorage.clear(); api.list.mockResolvedValue({ data: [application] }); });
afterEach(() => { wrapper?.destroy(); wrapper = null; localStorage.clear(); vi.restoreAllMocks(); });

it('reconstructs a frame after closing/reopening the host, only after catalog authorization', async () => {
  const first = mountHost(); await flush(); first.commit('workspaceApps/open', application); await flush();
  const oldFrame = wrapper.find('iframe').element;
  wrapper.destroy(); wrapper = null; expect(oldFrame.isConnected).toBe(false);
  const reopened = mountHost(); await flush();
  expect(reopened.state.workspaceApps.activeId).toBe(1);
  expect(wrapper.find('iframe').element).not.toBe(oldFrame); // Restoration is not execution while closed.
  expect(wrapper.find('iframe').attributes('src')).toBe(application.url);
});

it('retries restoration on online without an already mounted frame or a new background worker', async () => {
  const first = mountHost(); await flush(); first.commit('workspaceApps/open', application); wrapper.destroy(); wrapper = null;
  api.list.mockRejectedValueOnce(new Error('offline'));
  mountHost(); await flush(); expect(wrapper.find('iframe').exists()).toBe(false);
  window.dispatchEvent(new Event('online')); await flush();
  expect(wrapper.find('iframe').exists()).toBe(true);
});
