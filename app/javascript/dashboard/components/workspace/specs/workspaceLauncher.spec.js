import Vue from 'vue';
import Vuex from 'vuex';
import VTooltip from 'v-tooltip';
import { createLocalVue, mount } from '@vue/test-utils';
import WorkspaceLauncher from '../WorkspaceLauncher.vue';
import WorkspaceSidebar from '../WorkspaceSidebar.vue';
import module, { createState } from 'dashboard/store/modules/workspaceApps';
import { workspaceTooltip } from 'dashboard/helper/workspacePresentation.mjs';
import api from 'dashboard/api/workspaceApps';

vi.mock('dashboard/api/workspaceApps', () => ({ default: { list: vi.fn(), show: vi.fn() } }));
const localVue = createLocalVue();
localVue.use(Vuex);
// Exercise the real directive/Popper; a tooltip stub would not catch overlap.
localVue.use(VTooltip, { defaultHtml: false });
const stubs = { 'fluent-icon': true, WorkspaceIcon: true };
const application = id => ({ id, name: `App ${id}`, url: `https://app${id}.example.test`, launch_mode: 'embedded', enabled: true, integration_revision: 'one' });
const tick = async () => { for (let i = 0; i < 5; i += 1) await Vue.nextTick(); };
const createStore = () => {
  const store = new Vuex.Store({
    getters: { getCurrentRole: () => 'administrator', 'accounts/isRTL': () => false },
    modules: { workspaceApps: { ...module, state: createState() } },
  });
  store.commit('workspaceApps/reset', { accountId: 1, userId: 1 });
  store.commit('workspaceApps/catalog', [application(1), application(2)]);
  store.commit('workspaceApps/launcher', true);
  return store;
};
let wrapper;
afterEach(() => {
  wrapper?.destroy(); wrapper = null;
  vi.restoreAllMocks();
  document.body.innerHTML = '';
});

it('renders only app buttons, even for administrators, and focuses the catalog without an extra control', async () => {
  wrapper = mount(WorkspaceLauncher, { localVue, store: createStore(), stubs, mocks: { $t: key => key }, attachTo: document.body });
  await tick();
  expect(wrapper.findAll('.workspace-launcher__item').wrappers.map(item => item.attributes('aria-label'))).toEqual(['App 1', 'App 2']);
  expect(wrapper.find('a, router-link, [aria-label="WORKSPACE_APPS.CLOSE_CATALOG"], [aria-label="WORKSPACE_APPS.MANAGE"]').exists()).toBe(false);
  expect(document.activeElement).toBe(wrapper.element);
  expect(document.querySelector('.tooltip')).toBe(null);
});

it('closes the selector with Escape and restores focus to the main Applications toggle', async () => {
  const toggle = document.createElement('button');
  toggle.setAttribute('data-workspace-toggle', ''); document.body.appendChild(toggle);
  const store = createStore();
  wrapper = mount(WorkspaceLauncher, { localVue, store, stubs, mocks: { $t: key => key }, attachTo: document.body });
  await tick();
  document.dispatchEvent(new KeyboardEvent('keydown', { key: 'Escape', bubbles: true }));
  expect(store.state.workspaceApps.launcherOpen).toBe(false);
  expect(document.activeElement).toBe(toggle);
});

it('keeps click-away closing without closing the active application', async () => {
  const store = createStore();
  store.commit('workspaceApps/open', application(1));
  store.commit('workspaceApps/launcher', true);
  const frameKey = store.state.workspaceApps.tabs[0].key;
  wrapper = mount(WorkspaceLauncher, { localVue, store, stubs, mocks: { $t: key => key }, attachTo: document.body });
  await tick();
  document.body.click();
  expect(store.state.workspaceApps.launcherOpen).toBe(false);
  expect(store.state.workspaceApps.tabs[0].key).toBe(frameKey);
  expect(store.state.workspaceApps.activeId).toBe(1);
});

it('uses the existing main toggle to open and close the selector', async () => {
  const store = createStore();
  api.list.mockResolvedValue({ data: [application(1), application(2)] });
  wrapper = mount(WorkspaceSidebar, { localVue, store, stubs, mocks: { $t: key => key } });
  await wrapper.find('[data-workspace-toggle]').trigger('click');
  expect(store.state.workspaceApps.launcherOpen).toBe(false);
  await wrapper.find('[data-workspace-toggle]').trigger('click');
  expect(store.state.workspaceApps.launcherOpen).toBe(true);
});

it('opens an app and retracts the selector without needing a close button', async () => {
  const store = createStore();
  api.show.mockResolvedValue({ data: application(1) });
  wrapper = mount(WorkspaceLauncher, { localVue, store, stubs, mocks: { $t: key => key }, attachTo: document.body });
  await wrapper.find('.workspace-launcher__item').trigger('click'); await tick();
  expect(store.state.workspaceApps.activeId).toBe(1);
  expect(store.state.workspaceApps.launcherOpen).toBe(false);
});

// jsdom does not lay out elements. Supply measured rectangles, but leave the
// installed v-tooltip and Popper overflow/offset/flip algorithms unmocked.
const rect = (left, top, width, height) => ({ left, top, width, height, right: left + width, bottom: top + height, x: left, y: top });
function mockGeometry(railLeft, tooltipWidth = 120) {
  // jsdom returns empty computed border/margin values without a stylesheet;
  // Popper 1 parses those as numbers. Model the real browser's zero defaults.
  const style = document.createElement('style');
  style.textContent = 'html, body, .narrow-rail, .narrow-rail button, .tooltip, .tooltip * { margin: 0px; padding: 0px; border: 0px solid transparent; }';
  document.body.appendChild(style);
  vi.spyOn(HTMLElement.prototype, 'getBoundingClientRect').mockImplementation(function bounds() {
    if (this.classList.contains('tooltip')) return rect(0, 0, tooltipWidth, 24);
    if (this.classList.contains('tooltip-arrow')) return rect(0, 0, 0, 0);
    if (this.classList.contains('narrow-rail')) return rect(railLeft, 0, 64, 600);
    if (this.tagName === 'BUTTON') return rect(railLeft + 12, 80, 40, 40);
    return rect(0, 0, 1000, 700);
  });
  for (const [key, dimension] of Object.entries({ offsetWidth: 'width', clientWidth: 'width', offsetHeight: 'height', clientHeight: 'height' })) {
    const prototype = key.startsWith('client') ? Element.prototype : HTMLElement.prototype;
    vi.spyOn(prototype, key, 'get').mockImplementation(function size() { return this.getBoundingClientRect()[dimension]; });
  }
  vi.spyOn(HTMLElement.prototype, 'offsetParent', 'get').mockImplementation(function parent() {
    return this === document.documentElement ? null : document.documentElement;
  });
}

it.each([
  ['main', false, 0, 120], ['catalog', false, 64, 120],
  ['main RTL', true, 936, 120], ['catalog RTL', true, 872, 120],
  ['long name', false, 64, 340], ['long name RTL', true, 872, 340],
])('positions the %s hint beside the icon outside its narrow scroll parent', async (_, rtl, railLeft, width) => {
  mockGeometry(railLeft, width);
  let geometry;
  const options = { ...workspaceTooltip('Application name', rtl), delay: 0, popperOptions: {
    onCreate: data => { geometry = data; }, onUpdate: data => { geometry = data; },
  } };
  wrapper = mount({
    data: () => ({ options }),
    template: '<div class="narrow-rail" style="overflow-x: hidden; overflow-y: auto"><button v-tooltip="options">App</button></div>',
  }, { localVue, attachTo: document.body });
  const button = wrapper.find('button').element;
  button._tooltip.show();
  await vi.waitFor(() => { expect(geometry).toBeDefined(); });
  const tooltip = button._tooltip._tooltipNode;
  expect(tooltip.parentNode).toBe(document.body);
  expect(geometry.placement).toBe(rtl ? 'left' : 'right');
  expect(Number.isFinite(geometry.offsets.popper.left)).toBe(true);
  expect(Number.isFinite(geometry.offsets.popper.right)).toBe(true);
  const icon = button.getBoundingClientRect();
  if (rtl) expect(geometry.offsets.popper.right).toBeLessThanOrEqual(icon.left - 8);
  else expect(geometry.offsets.popper.left).toBeGreaterThanOrEqual(icon.right + 8);
  const boundary = button._tooltip.popperInstance.modifiers.find(modifier => modifier.name === 'preventOverflow');
  expect(boundary.boundariesElement).toBe('viewport');
});
