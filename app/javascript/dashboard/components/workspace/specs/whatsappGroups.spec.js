import { mount, createLocalVue } from '@vue/test-utils';
import Vue from 'vue';
import ChatTypeTabs from 'dashboard/components/widgets/ChatTypeTabs.vue';
import { applyPageFilters } from 'dashboard/store/modules/conversations/helpers';
import { useKeyboardEvents } from 'dashboard/composables/useKeyboardEvents';
vi.mock('dashboard/composables/useKeyboardEvents', () => ({ useKeyboardEvents: vi.fn() }));
const items = ['me', 'unassigned', 'all', 'groups'].map((key, i) => ({ key, name: ['Minha', 'Não atribuída', 'Todos', 'Grupos'][i], count: i === 3 ? 120 : i }));
const localVue = createLocalVue();
let wrapper;
afterEach(() => { wrapper?.destroy(); wrapper = null; vi.clearAllMocks(); });

it('places all four filters in one bounded tablist without introducing a sidebar width', async () => {
  wrapper = mount(ChatTypeTabs, { localVue, propsData: { items, activeTab: 'me' }, mocks: { $t: key => key }, attachTo: document.body });
  expect(wrapper.findAll('[role=tab]').length).toBe(4);
  expect(wrapper.findAll('[role=tab]').wrappers.map(tab => tab.text())).toEqual(['Minha0', 'Não atribuída1', 'Todos2', 'Grupos99+']);
  await wrapper.findAll('[role=tab]').at(3).trigger('click');
  expect(wrapper.emitted().chatTabChange[0]).toEqual(['groups']);
  await wrapper.setProps({ activeTab: 'groups' });
  expect(wrapper.findAll('[role=tab]').at(3).attributes('aria-selected')).toBe('true');
  await wrapper.findAll('[role=tab]').at(3).trigger('keydown', { key: 'ArrowRight', keyCode: 39 });
  await Vue.nextTick();
  expect(document.activeElement).toBe(wrapper.findAll('[role=tab]').at(0).element);
  const shortcuts = useKeyboardEvents.mock.calls[0][0]; shortcuts['Alt+KeyN'].action();
  expect(wrapper.emitted().chatTabChange.at(-1)).toEqual(['me']);
});

it('preserves the original three-tab component when groups are not available', () => {
  wrapper = mount(ChatTypeTabs, { localVue, propsData: { items: items.slice(0, 3) }, stubs: { 'hub-tabs': { template: '<div><slot/></div>' }, 'hub-tabs-item': true }, mocks: { $t: key => key } });
  expect(wrapper.find('.compact-chat-tabs').exists()).toBe(false);
  expect(wrapper.find('.tab--chat-type').exists()).toBe(true);
});

it('filters both fetched and realtime conversations by group identity, enabled inbox, status, labels and team', () => {
  const conversation = { is_group: true, inbox_id: 7, status: 'open', labels: ['support'], meta: { team: { id: 2 } } };
  const filter = { assigneeType: 'groups', groupInboxIds: [7], status: 'open', teamId: 2, labels: ['support'] };
  expect(applyPageFilters(conversation, filter)).toBe(true);
  for (const change of [{ is_group: false }, { inbox_id: 8 }, { status: 'resolved' }, { labels: [] }, { meta: { team: { id: 3 } } }]) {
    expect(applyPageFilters({ ...conversation, ...change }, filter)).toBe(false);
  }
  expect(applyPageFilters(conversation, { ...filter, groupInboxIds: [] })).toBe(false);
  expect(applyPageFilters({ ...conversation, is_group: false }, { ...filter, assigneeType: 'all' })).toBe(true);
});
