import Vue from 'vue';
import Vuex from 'vuex';
import { createLocalVue, mount } from '@vue/test-utils';
import WorkspaceHost from '../WorkspaceHost.vue';
import WorkspaceFrame from '../WorkspaceFrame.vue';
import module, { createState, mutations, actions } from 'dashboard/store/modules/workspaceApps';
import api from 'dashboard/api/workspaceApps';
import { submitApplicationLogin } from 'dashboard/helper/workspaceApps.mjs';

vi.mock('dashboard/api/workspaceApps', () => ({
  default: { list: vi.fn(), show: vi.fn(), credential: vi.fn(), launch: vi.fn(), forgetCredential: vi.fn() },
}));
const localVue = createLocalVue();
localVue.use(Vuex);
localVue.directive('tooltip', {});
const app = (id = 1) => ({
  id, name: `Test ${id}`, url: `https://app${id}.example.test/home`, enabled: true,
  launch_mode: 'embedded', auth_mode: 'session', icon_name: 'globe', integration_revision: 'revision-1',
});
const flush = async () => { for (let i = 0; i < 6; i += 1) await Vue.nextTick(); };
const deferred = () => { let resolve; const promise = new Promise(done => { resolve = done; }); return { promise, resolve }; };
const context = () => {
  const state = createState();
  mutations.reset(state, { accountId: 1, userId: 1 });
  return { state, commit: (name, payload) => mutations[name](state, payload) };
};
const stubs = { 'hub-modal': true, 'hub-button': true, 'fluent-icon': true, WorkspaceIcon: true };
let wrapper;
afterEach(() => { if (wrapper) wrapper.destroy(); wrapper = null; vi.restoreAllMocks(); document.body.innerHTML = ''; });

it('preserves real iframe elements when changing applications and returning to conversations', async () => {
  api.list.mockResolvedValue({ data: [app(), app(2)] });
  const store = new Vuex.Store({
    state: { accountId: 1, userId: 1 },
    getters: {
      getCurrentAccountId: state => state.accountId,
      isLoggedIn: state => !!state.userId,
      getCurrentUser: state => ({ id: state.userId }),
      'accounts/isRTL': () => false,
    },
    modules: { workspaceApps: { ...module, state: createState() } },
  });
  const route = Vue.observable({ fullPath: '/app/accounts/1/conversations/10' });
  wrapper = mount(WorkspaceHost, { localVue, store, stubs, mocks: { $t: key => key, $route: route }, attachTo: document.body });
  await flush();
  store.commit('workspaceApps/open', app());
  await flush();
  const firstFrame = wrapper.find('iframe').element;
  store.commit('workspaceApps/open', app(2));
  await flush();
  expect(wrapper.findAll('iframe').length).toBe(2);
  expect(wrapper.findAll('iframe').at(0).element).toBe(firstFrame);
  route.fullPath = '/app/accounts/1/conversations/20';
  await flush();
  expect(store.state.workspaceApps.activeId).toBe(null);
  expect(wrapper.findAll('iframe').at(0).element).toBe(firstFrame);
  store.commit('workspaceApps/open', app());
  await flush();
  expect(wrapper.findAll('iframe').at(0).element).toBe(firstFrame);
  expect(wrapper.findAll('iframe').length).toBe(2);
  store.commit('workspaceApps/catalog', [{ ...app(), name: 'Renamed' }, app(2)]);
  await flush();
  expect(wrapper.findAll('iframe').at(0).element).toBe(firstFrame);
  store.commit('workspaceApps/close', 1);
  await flush();
  expect(firstFrame.isConnected).toBe(false);
  expect(wrapper.findAll('iframe').length).toBe(1);
  store.state.accountId = 2;
  await flush();
  expect(wrapper.findAll('iframe').length).toBe(0);
});

it('switches an already open application without a network request or new key', async () => {
  const ctx = context();
  mutations.open(ctx.state, app());
  const key = ctx.state.tabs[0].key;
  mutations.deactivate(ctx.state);
  await actions.open(ctx, 1);
  expect(api.show).not.toHaveBeenCalled();
  expect(ctx.state.tabs[0].key).toBe(key);
  expect(ctx.state.activeId).toBe(1);
});

it('keeps frames on connectivity errors but closes them on access revocation', async () => {
  const ctx = context();
  mutations.open(ctx.state, app());
  api.list.mockRejectedValueOnce(new Error('offline'));
  await actions.refresh(ctx);
  expect(ctx.state.tabs.length).toBe(1);
  api.list.mockRejectedValueOnce({ response: { status: 403 } });
  await actions.refresh(ctx);
  expect(ctx.state.tabs.length).toBe(0);
});

it('rejects a stale response even after switching from company A to B and back to A', async () => {
  const ctx = context();
  const pending = deferred();
  api.list.mockReturnValue(pending.promise);
  const task = actions.refresh(ctx);
  mutations.reset(ctx.state, { accountId: 2, userId: 1 });
  mutations.reset(ctx.state, { accountId: 1, userId: 1 });
  pending.resolve({ data: [app()] });
  await task;
  expect(ctx.state.apps).toEqual([]);
});

it('does not open a delayed application after the user returned to a native screen', async () => {
  const ctx = context();
  const pending = deferred();
  api.show.mockReturnValue(pending.promise);
  const task = actions.open(ctx, 1);
  mutations.deactivate(ctx.state);
  pending.resolve({ data: app() });
  await task;
  expect(ctx.state.tabs).toEqual([]);
});

it('submits only configured credentials in an external POST and wipes temporary fields', () => {
  const integration = { ...app(), auth_mode: 'form_post', login_url: 'https://app1.example.test/login', username_field: 'user[email]', password_field: 'user[password]' };
  const frame = document.createElement('iframe');
  frame.name = 'workspace-test';
  document.body.appendChild(frame);
  const payload = { action: integration.login_url, username_field: integration.username_field, password_field: integration.password_field, username: 'test-user', password: 'test-secret', integration_revision: integration.integration_revision };
  const submission = vi.spyOn(HTMLFormElement.prototype, 'submit').mockImplementation(function submit() {
    expect(this.method).toBe('post');
    expect(this.action).toBe(integration.login_url);
    expect(this.target).toBe(frame.name);
    expect(Array.from(this.elements).map(element => element.name)).toEqual(['user[email]', 'user[password]']);
  });
  submitApplicationLogin(document, frame, integration, payload, window.location.origin);
  expect(submission).toHaveBeenCalledTimes(1);
  expect(document.querySelector('form')).toBe(null);
  expect(payload.password).toBe('');
  expect(payload.username).toBe('');
});

it('rejects a mismatched credential destination before making any submission', () => {
  const frame = document.createElement('iframe');
  frame.name = 'workspace-test';
  document.body.appendChild(frame);
  const payload = { action: 'https://another.example.test', username: 'test', password: 'secret' };
  const submission = vi.spyOn(HTMLFormElement.prototype, 'submit');
  expect(() => submitApplicationLogin(document, frame, app(), payload, window.location.origin)).toThrow();
  expect(submission).not.toHaveBeenCalled();
});

it('does not release a delayed login into a frame that has already been closed', async () => {
  const integration = { ...app(), auth_mode: 'form_post', login_url: 'https://app1.example.test/login', username_field: 'username', password_field: 'password' };
  api.credential.mockResolvedValue({ data: { saved: false } });
  wrapper = mount(WorkspaceFrame, { localVue, propsData: { app: integration, accountId: 1 }, stubs, mocks: { $t: key => key }, attachTo: document.body });
  await flush();
  const pending = deferred();
  api.launch.mockReturnValue(pending.promise);
  const submission = vi.spyOn(HTMLFormElement.prototype, 'submit');
  const payload = { action: integration.login_url, username_field: 'username', password_field: 'password', username: 'test', password: 'secret', integration_revision: 'revision-1' };
  const task = wrapper.vm.login(true);
  wrapper.destroy();
  wrapper = null;
  pending.resolve({ data: payload });
  await task;
  expect(submission).not.toHaveBeenCalled();
  expect(payload.password).toBe('');
});
