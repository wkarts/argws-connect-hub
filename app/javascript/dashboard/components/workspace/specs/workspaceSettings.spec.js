import Vue from 'vue';
import Vuex from 'vuex';
import axios from 'axios';
import { createLocalVue, mount } from '@vue/test-utils';
import WorkspaceSettings from 'dashboard/routes/dashboard/settings/workspaceApps/Index.vue';

// Keep this unit test on the settings form, not the router imported by its header.
vi.mock('dashboard/routes/dashboard/settings/components/BaseSettingsHeader.vue', () => ({ default: { render: h => h('header') } }));
vi.mock('dashboard/routes/dashboard/settings/SettingsLayout.vue', () => ({ default: { render: h => h('div') } }));

const localVue = createLocalVue();
localVue.use(Vuex);
const tick = async () => { for (let i = 0; i < 15; i += 1) await Vue.nextTick(); };
const existing = { id: 1, name: 'Existing app', url: 'https://existing.example.test', enabled: true, allowed_user_ids: [] };
const stubs = {
  WorkspaceIcon: true, BaseSettingsHeader: true, multiselect: true, 'hub-button': true,
  SettingsLayout: { template: '<div><slot name="header"/><slot name="preBody"/><slot name="body"/><slot/></div>' },
  'hub-modal': { props: ['show'], template: '<div v-if="show"><slot/></div>' },
};
let wrapper;
let requests;
beforeEach(() => {
  requests = [];
  // Use the real Axios request transformer, including its FormData handling.
  vi.stubGlobal('axios', axios.create({ adapter: async config => {
    requests.push(config);
    let data = { id: 2 };
    if (config.url.endsWith('/manage')) data = [existing];
    if (config.url.endsWith('/agents')) data = [{ id: 7, name: 'Company administrator' }];
    return { data, status: config.method === 'post' ? 201 : 200, statusText: 'OK', headers: {}, config };
  } }));
});
afterEach(() => { wrapper?.destroy(); wrapper = null; vi.unstubAllGlobals(); vi.restoreAllMocks(); });

async function settings() {
  const store = new Vuex.Store({ getters: { getCurrentAccountId: () => 1 }, modules: { workspaceApps: { namespaced: true, actions: { refresh: vi.fn() } } } });
  wrapper = mount(WorkspaceSettings, { localVue, store, stubs, mocks: { $t: key => key } });
  await tick();
  wrapper.vm.edit();
  wrapper.vm.form.name = 'New application';
  wrapper.vm.form.url = 'https://app.example.test/manager/login';
  return wrapper;
}

it('submits a complete JSON form through Axios while another application already exists', async () => {
  await settings();
  await wrapper.vm.save();
  const sent = requests.find(request => request.method === 'post');
  expect(sent).toBeDefined();
  expect(JSON.parse(sent.data).workspace_app).toMatchObject({ name: 'New application', enabled: true, auth_mode: 'session', allowed_user_ids: [] });
  expect(wrapper.vm.error).toBe('');
  expect(wrapper.vm.showForm).toBe(false);
});

it('submits an icon and selected users through the real Axios FormData transformer', async () => {
  await settings();
  wrapper.vm.iconFile = new File(['png'], 'icon.png', { type: 'image/png' });
  wrapper.vm.form.access_mode = 'selected';
  wrapper.vm.selectedUsers = [{ id: 7, name: 'Company administrator' }];
  await wrapper.vm.save();
  const sent = requests.find(request => request.method === 'post');
  expect(sent).toBeDefined();
  expect(sent.data).toBeInstanceOf(FormData);
  expect(sent.data.get('workspace_app[icon]')).toBeInstanceOf(File);
  expect(sent.data.getAll('workspace_app[allowed_user_ids][]')).toEqual(['7']);
  expect(sent.data.get('workspace_app[allow_auto_login]')).toBe('false');
  expect(wrapper.vm.error).toBe('');
  expect(wrapper.vm.showForm).toBe(false);
});

it('keeps the backend error and request ID instead of hiding them behind a generic save message', async () => {
  await settings();
  axiosForFailure({ error: 'param is missing or the value is empty: icon_file' });
  await wrapper.vm.save();
  expect(wrapper.vm.error).toContain('icon_file');
  expect(wrapper.vm.error).toContain('HTTP 422');
  expect(wrapper.vm.error).toContain('test-request-id');
  expect(wrapper.vm.showForm).toBe(true);
  expect(wrapper.vm.form.name).toBe('New application');
  expect(wrapper.vm.saving).toBe(false);
});

it('does not render raw HTML error pages from a proxy', async () => {
  await settings();
  axiosForFailure('<html>Proxy failure</html>');
  await wrapper.vm.save();
  expect(wrapper.vm.error).toContain('WORKSPACE_APPS.SAVE_ERROR');
  expect(wrapper.vm.error).toContain('HTTP 422');
  expect(wrapper.vm.error).not.toContain('<html>');
});

function axiosForFailure(data) {
  window.axios.defaults.adapter = config => Promise.reject({ response: { data, status: 422, headers: { 'x-request-id': 'test-request-id' }, config } });
}
