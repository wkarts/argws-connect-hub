<script>
import { mapGetters } from 'vuex';
import { useAlert } from 'dashboard/composables';
import HubDropdownItem from 'shared/components/ui/dropdown/DropdownItem.vue';
import HubDropdownMenu from 'shared/components/ui/dropdown/DropdownMenu.vue';
import HubDropdownHeader from 'shared/components/ui/dropdown/DropdownHeader.vue';
import HubDropdownDivider from 'shared/components/ui/dropdown/DropdownDivider.vue';
import AvailabilityStatusBadge from '../widgets/conversation/AvailabilityStatusBadge.vue';
import hubConstants from 'dashboard/constants/globals';

const { AVAILABILITY_STATUS_KEYS } = hubConstants;

export default {
  components: {
    HubDropdownHeader,
    HubDropdownDivider,
    HubDropdownMenu,
    HubDropdownItem,
    AvailabilityStatusBadge,
  },
  data() {
    return {
      isStatusMenuOpened: false,
      isUpdating: false,
    };
  },

  computed: {
    ...mapGetters({
      getCurrentUserAvailability: 'getCurrentUserAvailability',
      currentAccountId: 'getCurrentAccountId',
      currentUserAutoOffline: 'getCurrentUserAutoOffline',
    }),
    availabilityDisplayLabel() {
      const availabilityIndex = AVAILABILITY_STATUS_KEYS.findIndex(
        key => key === this.currentUserAvailability
      );
      return this.$t('PROFILE_SETTINGS.FORM.AVAILABILITY.STATUSES_LIST')[
        availabilityIndex
      ];
    },
    currentUserAvailability() {
      return this.getCurrentUserAvailability;
    },
    availabilityStatuses() {
      return this.$t('PROFILE_SETTINGS.FORM.AVAILABILITY.STATUSES_LIST').map(
        (statusLabel, index) => ({
          label: statusLabel,
          value: AVAILABILITY_STATUS_KEYS[index],
          disabled:
            this.currentUserAvailability === AVAILABILITY_STATUS_KEYS[index],
        })
      );
    },
  },

  methods: {
    openStatusMenu() {
      this.isStatusMenuOpened = true;
    },
    closeStatusMenu() {
      this.isStatusMenuOpened = false;
    },
    updateAutoOffline(autoOffline) {
      this.$store.dispatch('updateAutoOffline', {
        accountId: this.currentAccountId,
        autoOffline,
      });
    },
    changeAvailabilityStatus(availability) {
      if (this.isUpdating) {
        return;
      }

      this.isUpdating = true;
      try {
        this.$store.dispatch('updateAvailability', {
          availability,
          account_id: this.currentAccountId,
        });
      } catch (error) {
        useAlert(
          this.$t('PROFILE_SETTINGS.FORM.AVAILABILITY.SET_AVAILABILITY_ERROR')
        );
      } finally {
        this.isUpdating = false;
      }
    },
  },
};
</script>

<template>
  <HubDropdownMenu>
    <HubDropdownHeader :title="$t('SIDEBAR.SET_AVAILABILITY_TITLE')" />
    <HubDropdownItem
      v-for="status in availabilityStatuses"
      :key="status.value"
      class="flex items-baseline"
    >
      <hub-button
        size="small"
        :color-scheme="status.disabled ? '' : 'secondary'"
        :variant="status.disabled ? 'smooth' : 'clear'"
        class-names="status-change--dropdown-button"
        @click="changeAvailabilityStatus(status.value)"
      >
        <AvailabilityStatusBadge :status="status.value" />
        {{ status.label }}
      </hub-button>
    </HubDropdownItem>
    <HubDropdownDivider />
    <HubDropdownItem class="flex items-center justify-between p-2 m-0">
      <div class="flex items-center">
        <fluent-icon
          v-tooltip.right-start="$t('SIDEBAR.SET_AUTO_OFFLINE.INFO_TEXT')"
          icon="info"
          size="14"
          class="mt-px"
        />

        <span
          class="mx-1 my-0 text-xs font-medium text-slate-600 dark:text-slate-100"
        >
          {{ $t('SIDEBAR.SET_AUTO_OFFLINE.TEXT') }}
        </span>
      </div>

      <hub-switch
        size="small"
        class="mx-1 mt-px mb-0"
        :value="currentUserAutoOffline"
        @input="updateAutoOffline"
      />
    </HubDropdownItem>
    <HubDropdownDivider />
  </HubDropdownMenu>
</template>
