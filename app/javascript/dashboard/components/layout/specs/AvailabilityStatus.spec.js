import AvailabilityStatus from '../AvailabilityStatus.vue';
import { createLocalVue, mount } from '@vue/test-utils';
import Vuex from 'vuex';
import VueI18n from 'vue-i18n';
import VTooltip from 'v-tooltip';

import HubButton from 'dashboard/components/ui/HubButton.vue';
import HubDropdownItem from 'shared/components/ui/dropdown/DropdownItem.vue';
import HubDropdownMenu from 'shared/components/ui/dropdown/DropdownMenu.vue';
import HubDropdownHeader from 'shared/components/ui/dropdown/DropdownHeader.vue';
import HubDropdownDivider from 'shared/components/ui/dropdown/DropdownDivider.vue';
import FluentIcon from 'shared/components/FluentIcon/DashboardIcon.vue';

import i18n from 'dashboard/i18n';

const localVue = createLocalVue();
localVue.use(VTooltip, {
  defaultHtml: false,
});
localVue.use(Vuex);
localVue.use(VueI18n);
localVue.component('hub-button', HubButton);
localVue.component('hub-dropdown-header', HubDropdownHeader);
localVue.component('hub-dropdown-menu', HubDropdownMenu);
localVue.component('hub-dropdown-divider', HubDropdownDivider);
localVue.component('hub-dropdown-item', HubDropdownItem);
localVue.component('fluent-icon', FluentIcon);

const i18nConfig = new VueI18n({ locale: 'en', messages: i18n });

describe('AvailabilityStatus', () => {
  const currentAvailability = 'online';
  const currentAccountId = '1';
  const currentUserAutoOffline = false;
  let store = null;
  let actions = null;
  let modules = null;
  let availabilityStatus = null;

  beforeEach(() => {
    actions = {
      updateAvailability: vi.fn(() => {
        return Promise.resolve();
      }),
    };

    modules = {
      auth: {
        getters: {
          getCurrentUserAvailability: () => currentAvailability,
          getCurrentAccountId: () => currentAccountId,
          getCurrentUserAutoOffline: () => currentUserAutoOffline,
        },
      },
    };

    store = new Vuex.Store({ actions, modules });

    availabilityStatus = mount(AvailabilityStatus, {
      store,
      localVue,
      i18n: i18nConfig,
      stubs: { HubSwitch: { template: '<button />' } },
    });
  });

  it('dispatches an action when user changes status', async () => {
    await availabilityStatus;
    availabilityStatus
      .findAll('.status-change--dropdown-button')
      .at(2)
      .trigger('click');

    expect(actions.updateAvailability).toBeCalledWith(
      expect.any(Object),
      { availability: 'offline', account_id: currentAccountId },
      undefined
    );
  });
});
