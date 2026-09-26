import Vue from 'vue';
import Vuex from 'vuex';
import { createLocalVue, mount } from '@vue/test-utils';
import GroupSettings from 'dashboard/routes/dashboard/settings/inbox/settingsPage/WhatsappGroupSettings.vue';
import GroupThread from 'dashboard/components/whatsappGroups/GroupThread.vue';
import { groupDestination, mergeGroupMessages } from 'dashboard/helper/whatsappGroups.mjs';
import api from 'dashboard/api/whatsappGroups';

vi.mock('dashboard/api/whatsappGroups', () => ({ default: {
  settings: vi.fn(), saveSettings: vi.fn(), sync: vi.fn(), saveGroup: vi.fn(), bulk: vi.fn(), replay: vi.fn(),
  list: vi.fn(), show: vi.fn(), messages: vi.fn(), message: vi.fn(), send: vi.fn(), revoke: vi.fn(), cancel: vi.fn(), preference: vi.fn(),
} }));
const localVue = createLocalVue(); localVue.use(Vuex);
const tick = async () => { for (let index = 0; index < 20; index += 1) await Vue.nextTick(); };
const group = { id: 9, inbox_id: 3, name: 'Diretoria', jid: '120363000000000009@g.us', treatment: 'management',
  selected: true, access_mode: 'inbox', allowed_user_ids: [], lock_version: 2, can_reply: true, muted: false,
  impact: { active_tickets: 0, pending_messages: 0 }, pending_events: 0 };
const message = { id: 1, source_id: 'GROUP-1', content: 'Conteúdo privado', direction: 'incoming', status: 'received', kind: 'text', files: [], sender_name: 'Participante', sent_at: '2026-09-26T03:00:00Z' };
const configuration = { enabled: true, settings: { selection_mode: 'selected', default_treatment: 'management', default_access_mode: 'inbox', default_user_ids: [], lock_version: 4 },
  users: [{ id: 1, name: 'Admin' }], groups: [group], total: 1, page: 1 };
const stubs = { 'hub-button': { props: ['disabled'], template: `<button :disabled="disabled" @click="$emit('click')"><slot/></button>` },
  'fluent-icon': true, 'hub-modal': { template: '<div><slot/></div>' } };
let wrapper;
const createStore = () => new Vuex.Store({ getters: { getCurrentAccountId: () => 1 }, modules: { inboxes: { namespaced: true, actions: { get: vi.fn() } } } });
const mocks = () => ({ $t: key => key, $route: { query: {}, params: { inbox_id: 3 } }, $router: { push: vi.fn().mockResolvedValue() }, $emitter: { on: vi.fn(), off: vi.fn() } });
beforeEach(() => {
  api.settings.mockResolvedValue({ data: JSON.parse(JSON.stringify(configuration)) });
  api.saveSettings.mockResolvedValue({ data: configuration }); api.saveGroup.mockResolvedValue({ data: group });
  api.show.mockResolvedValue({ data: { ...group } }); api.messages.mockResolvedValue({ data: { messages: [{ ...message }], next_before: null } });
  api.preference.mockResolvedValue({ data: { ...group, muted: true } });
});
afterEach(() => { wrapper?.destroy(); wrapper = null; vi.clearAllMocks(); vi.restoreAllMocks(); });

it('keeps group policy and content users in the inbox configuration with optimistic versions', async () => {
  wrapper = mount(GroupSettings, { localVue, store: createStore(), stubs, propsData: { inbox: { id: 3 } }, mocks: mocks() }); await tick();
  expect(api.settings).toHaveBeenCalledWith(1, 3, { page: 1, q: '' });
  wrapper.vm.settings.default_treatment = 'conversation'; wrapper.vm.saveSettings(); await tick();
  expect(api.saveSettings).toHaveBeenCalledWith(1, 3, { settings: expect.objectContaining({ default_treatment: 'conversation', lock_version: 4 }), enabled: true });
});
it('does not silently save a group treatment change without confirmation', async () => {
  wrapper = mount(GroupSettings, { localVue, store: createStore(), stubs, propsData: { inbox: { id: 3 } }, mocks: mocks() }); await tick();
  wrapper.vm.editGroup(group); wrapper.vm.edit.treatment = 'conversation';
  const pending = wrapper.vm.saveGroup(); await tick(); expect(api.saveGroup).not.toHaveBeenCalled();
  wrapper.vm.finishConfirmation(false); await pending; expect(api.saveGroup).not.toHaveBeenCalled();
});
it('does not create a ticket simply by selecting a management group', () => {
  expect(groupDestination(1, group)).toEqual({ name: 'inbox_dashboard', params: { accountId: 1, inbox_id: 3 }, query: { groupId: '9', groupTab: '1' } });
  expect(groupDestination(1, { ...group, treatment: 'conversation', conversation_id: 42 })).toEqual({ name: 'conversation_through_inbox', params: { accountId: 1, inbox_id: 3, conversation_id: 42 }, query: { groupTab: '1' } });
});
it('clears management content immediately on access invalidation and does not show a revoked history', async () => {
  wrapper = mount(GroupThread, { localVue, store: createStore(), stubs, propsData: { groupId: 9 }, mocks: mocks() }); await tick();
  expect(wrapper.text()).toContain('Conteúdo privado');
  wrapper.vm.changed({ account_id: 1, inbox_id: 3, group_id: 9, invalidated: true });
  await Vue.nextTick(); expect(wrapper.text()).not.toContain('Conteúdo privado');
  api.show.mockRejectedValue({ response: { status: 404 } }); await wrapper.vm.refresh();
  expect(wrapper.vm.group).toBeNull(); expect(wrapper.vm.messages).toEqual([]);
});
it('does not offer the management composer for a support group or read-only legacy history', async () => {
  api.show.mockResolvedValue({ data: { ...group, treatment: 'conversation', conversation_id: 5 } });
  wrapper = mount(GroupThread, { localVue, store: createStore(), stubs, propsData: { groupId: 9 }, mocks: mocks() }); await tick();
  expect(wrapper.find('textarea').exists()).toBe(false);
  await wrapper.setData({ group: { ...group }, legacy: true }); expect(wrapper.find('textarea').exists()).toBe(false);
});
it('updates personal mute without writing group administration', async () => {
  wrapper = mount(GroupThread, { localVue, store: createStore(), stubs, propsData: { groupId: 9 }, mocks: mocks() }); await tick();
  await wrapper.vm.toggleMute(); expect(api.preference).toHaveBeenCalledWith(1, 9, { muted: true });
  expect(api.saveGroup).not.toHaveBeenCalled(); expect(wrapper.vm.group.muted).toBe(true);
});
it('merges repeated realtime fetches without duplicating a message', () => {
  expect(mergeGroupMessages([message], [{ ...message, status: 'read' }])).toEqual([{ ...message, status: 'read' }]);
});
it('ignores a late response from the previously selected group', async () => {
  let resolve;
  api.show.mockImplementationOnce(() => new Promise(done => { resolve = done; }));
  wrapper = mount(GroupThread, { localVue, store: createStore(), stubs, propsData: { groupId: 9 }, mocks: mocks() }); await tick();
  api.show.mockResolvedValue({ data: { ...group, id: 10, name: 'Outro grupo' } });
  await wrapper.setProps({ groupId: 10 }); await tick();
  resolve({ data: group }); await tick(); expect(wrapper.vm.group.id).toBe(10);
});

it('submits multipart data only to the explicit group endpoint and retains one client identity on retry', async () => {
  wrapper = mount(GroupThread, { localVue, store: createStore(), stubs, propsData: { groupId: 9 }, mocks: mocks() }); await tick();
  wrapper.vm.text = 'Resposta gerencial';
  api.send.mockRejectedValueOnce(new Error('network'));
  await wrapper.vm.send();
  const first = api.send.mock.calls[0][2];
  expect(first.get('group_message[content]')).toBe('Resposta gerencial');
  expect(first.get('group_message[client_id]')).toMatch(/^[0-9a-f-]{36}$/);
  api.send.mockResolvedValueOnce({ data: { ...message, id: 2, direction: 'outgoing', status: 'queued' } });
  await wrapper.vm.send();
  expect(api.send.mock.calls[1][2].get('group_message[client_id]')).toBe(first.get('group_message[client_id]'));
  expect(api.send.mock.calls[1].slice(0, 2)).toEqual([1, 9]);
});


it('does not reinsert a late send response after realtime access revocation', async () => {
  wrapper = mount(GroupThread, { localVue, store: createStore(), stubs, propsData: { groupId: 9 }, mocks: mocks() }); await tick();
  let finishSend;
  api.send.mockImplementationOnce(() => new Promise(resolve => { finishSend = resolve; }));
  wrapper.vm.text = 'Texto em envio';
  const sending = wrapper.vm.send();
  wrapper.vm.changed({ account_id: 1, inbox_id: 3, group_id: 9, invalidated: true });
  api.show.mockRejectedValue({ response: { status: 404 } });
  finishSend({ data: { ...message, id: 2, direction: 'outgoing', status: 'queued' } });
  await sending; await tick();
  expect(wrapper.vm.group).toBeNull(); expect(wrapper.vm.messages).toEqual([]);
  expect(wrapper.text()).not.toContain('Conteúdo privado');
  expect(wrapper.find('textarea').exists()).toBe(false);
});

it('does not mix a send response into the historical ticket view', async () => {
  wrapper = mount(GroupThread, { localVue, store: createStore(), stubs, propsData: { groupId: 9 }, mocks: mocks() }); await tick();
  let finishSend;
  api.send.mockImplementationOnce(() => new Promise(resolve => { finishSend = resolve; }));
  wrapper.vm.text = 'Saída gerencial'; const sending = wrapper.vm.send();
  await wrapper.setData({ legacy: true, messages: [{ ...message, id: 90 }] });
  finishSend({ data: { ...message, id: 2, direction: 'outgoing' } }); await sending; await tick();
  expect(wrapper.vm.messages.map(row => row.id)).toEqual([90]);
  expect(wrapper.find('textarea').exists()).toBe(false);
});
