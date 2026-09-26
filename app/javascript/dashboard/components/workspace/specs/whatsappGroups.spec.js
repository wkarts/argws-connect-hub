import { mount, createLocalVue } from '@vue/test-utils';
import Vue from 'vue';
import ChatTypeTabs from 'dashboard/components/widgets/ChatTypeTabs.vue';
import HubTabs from 'dashboard/components/ui/Tabs/Tabs.js';
import HubTabsItem from 'dashboard/components/ui/Tabs/TabsItem.vue';
import { applyPageFilters } from 'dashboard/store/modules/conversations/helpers';
import { useKeyboardEvents } from 'dashboard/composables/useKeyboardEvents';
vi.mock('dashboard/composables/useKeyboardEvents', () => ({ useKeyboardEvents: vi.fn() }));
const items = ['me', 'unassigned', 'all', 'groups'].map((key, i) => ({ key, name: ['Minha', 'Não atribuída', 'Todos', 'Grupos'][i], count: i === 3 ? 120 : i }));
const localVue = createLocalVue();
localVue.component('hub-tabs', HubTabs);
localVue.component('hub-tabs-item', HubTabsItem);
let wrapper;
afterEach(() => { wrapper?.destroy(); wrapper = null; vi.clearAllMocks(); });

it('keeps all four filters inside the original HUB tabs component', async () => {
  wrapper = mount(ChatTypeTabs, {
    localVue,
    propsData: { items, activeTab: 'me' },
    mocks: { $t: key => key },
    attachTo: document.body,
  });

  const tabs = wrapper.findAll('.tabs-title');
  expect(tabs.length).toBe(4);
  expect(tabs.wrappers.map(tab => tab.text().replace(/\s+/g, ' ').trim())).toEqual([
    'Minha 0',
    'Não atribuída 1',
    'Todos 2',
    'Grupos 120',
  ]);
  expect(wrapper.find('.tab--chat-type-four').exists()).toBe(true);
  expect(tabs.at(0).classes()).toContain('is-active');

  await tabs.at(3).find('a').trigger('click');
  expect(wrapper.emitted().chatTabChange[0]).toEqual(['groups']);

  await wrapper.setProps({ activeTab: 'groups' });
  await Vue.nextTick();
  expect(wrapper.findAll('.tabs-title').at(3).classes()).toContain('is-active');

  const shortcuts = useKeyboardEvents.mock.calls[0][0];
  shortcuts['Alt+KeyN'].action();
  expect(wrapper.emitted().chatTabChange.at(-1)).toEqual(['me']);
});

it('preserves the original three-tab component when groups are not available', () => {
  wrapper = mount(ChatTypeTabs, { localVue, propsData: { items: items.slice(0, 3) }, mocks: { $t: key => key } });
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
