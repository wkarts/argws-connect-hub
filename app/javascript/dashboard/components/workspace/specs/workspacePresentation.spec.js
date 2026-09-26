import Vue from 'vue';
import Vuex from 'vuex';
import { createLocalVue, mount } from '@vue/test-utils';
import WorkspaceHost from '../WorkspaceHost.vue';
import WorkspaceToolbar from '../WorkspaceToolbar.vue';
import WorkspaceFrame from '../WorkspaceFrame.vue';
import WorkspaceRail from '../WorkspaceRail.vue';
import module, { createState } from 'dashboard/store/modules/workspaceApps';
import api from 'dashboard/api/workspaceApps';

vi.mock('dashboard/api/workspaceApps', () => ({ default: { list: vi.fn(), show: vi.fn(), credential: vi.fn(), launch: vi.fn(), forgetCredential: vi.fn(), diagnose: vi.fn() } }));
const localVue = createLocalVue();
localVue.use(Vuex);
localVue.directive('tooltip', {});
const application = id => ({ id, name: `App ${id}`, url: `https://app${id}.example.test`, launch_mode: 'embedded', auth_mode: 'session', enabled: true, integration_revision: 'one' });
const stubs = { 'fluent-icon': true, 'hub-button': true, WorkspaceIcon: true, 'hub-modal': { props: ['show'], template: '<div v-if="show" class="test-modal"><slot /></div>' } };
const tick = async () => { for (let i = 0; i < 5; i += 1) await Vue.nextTick(); };
let wrapper;
afterEach(() => { wrapper?.destroy(); wrapper = null; vi.useRealTimers(); vi.restoreAllMocks(); localStorage.clear(); document.body.innerHTML = ''; });

it('auto-hides a compact toolbar, pins it and restores the preference for the same member', async () => {
  vi.useFakeTimers();
  const options = { localVue, propsData: { app: application(1), scope: '1:4' }, mocks: { $t: key => key }, stubs, attachTo: document.body };
  wrapper = mount(WorkspaceToolbar, options);
  expect(wrapper.vm.pinned).toBe(false);
  vi.advanceTimersByTime(1700); await tick();
  expect(wrapper.vm.shown).toBe(false);
  wrapper.vm.reveal(); wrapper.vm.togglePin(); await tick();
  expect(wrapper.vm.pinned).toBe(true);
  expect(wrapper.emitted('pin').at(-1)).toEqual([true]);
  wrapper.destroy(); wrapper = mount(WorkspaceToolbar, options);
  expect(wrapper.vm.pinned).toBe(true);
});

it('keeps navigation buttons disabled until the destination enables a safe bridge', async () => {
  wrapper = mount(WorkspaceToolbar, { localVue, propsData: { app: application(1) }, stubs, mocks: { $t: key => key } });
  expect(wrapper.find('[aria-label="WORKSPACE_APPS.NAV_BACK"]').element.disabled).toBe(true);
  await wrapper.setProps({ navigation: { ready: true, back: true, forward: false } });
  await wrapper.find('[aria-label="WORKSPACE_APPS.NAV_BACK"]').trigger('click');
  expect(wrapper.emitted('navigate')).toEqual([['back']]);
});

it('does not destroy frames while hiding controls or opening diagnostics', async () => {
  api.diagnose.mockResolvedValue({ data: { code: 'headers_checked', verdict: 'no_block_observed', hub_origin: window.location.origin, steps: [] } });
  wrapper = mount(WorkspaceFrame, { localVue, propsData: { app: application(1), accountId: 1 }, stubs, mocks: { $t: key => key }, attachTo: document.body });
  const frame = wrapper.find('iframe').element;
  await wrapper.setData({ pinned: true, showDiagnostics: true }); await tick();
  expect(wrapper.find('iframe').element).toBe(frame);
  expect(api.diagnose).toHaveBeenCalledTimes(1);
  await wrapper.setData({ showDiagnostics: false, pinned: false });
  expect(wrapper.find('iframe').element).toBe(frame);
});

it('allows context-menu close from a conversation without activating or closing other frames', async () => {
  api.list.mockResolvedValue({ data: [application(1), application(2)] });
  const store = new Vuex.Store({ getters: { getCurrentAccountId: () => 1, isLoggedIn: () => true, getCurrentUser: () => ({ id: 1 }), 'accounts/isRTL': () => false }, modules: { workspaceApps: { ...module, state: createState() } } });
  wrapper = mount(WorkspaceHost, { localVue, store, stubs, mocks: { $t: key => key, $route: { fullPath: '/app/1' } }, attachTo: document.body });
  await tick(); store.commit('workspaceApps/open', application(1)); store.commit('workspaceApps/open', application(2)); await tick();
  const second = wrapper.findAll('iframe').at(1).element;
  store.commit('workspaceApps/deactivate');
  store.commit('workspaceApps/context', { id: 1, x: 45, y: 200 }); await tick();
  await wrapper.find('.workspace-context button').trigger('click');
  expect(wrapper.find('.test-modal').exists()).toBe(true);
  wrapper.vm.performAction(); await tick();
  expect(store.state.workspaceApps.tabs.map(tab => tab.id)).toEqual([2]);
  expect(wrapper.find('iframe').element).toBe(second);
  expect(store.state.workspaceApps.activeId).toBe(null);
  await wrapper.setProps({ available: false });
  expect(wrapper.find('iframe').element).toBe(second);
});

it('preserves the selected frame when closing other applications', () => {
  const state = createState();
  module.mutations.reset(state, { accountId: 1, userId: 1 });
  module.mutations.open(state, application(1)); module.mutations.open(state, application(2));
  const key = state.tabs[0].key;
  module.mutations.closeOthers(state, 1);
  expect(state.tabs).toHaveLength(1); expect(state.tabs[0].key).toBe(key);
});

it('scrolls a bounded rail by wheel-compatible scrollTop and supports keyboard traversal', async () => {
  wrapper = mount(WorkspaceRail, { localVue, propsData: { label: 'Apps' }, stubs, mocks: { $t: key => key }, slots: { default: '<button>A</button><button>B</button>' }, attachTo: document.body });
  const view = wrapper.vm.$refs.viewport;
  Object.defineProperty(view, 'clientHeight', { value: 100 });
  Object.defineProperty(view, 'scrollHeight', { value: 600 });
  wrapper.vm.measure(); expect(wrapper.vm.canDown).toBe(true);
  wrapper.vm.scroll(1); expect(view.scrollTop).toBe(70);
  const buttons = wrapper.vm.$refs.items.querySelectorAll('button');
  buttons[0].focus();
  view.dispatchEvent(new KeyboardEvent('keydown', { key: 'ArrowDown', bubbles: true }));
  expect(document.activeElement).toBe(buttons[1]);
});
