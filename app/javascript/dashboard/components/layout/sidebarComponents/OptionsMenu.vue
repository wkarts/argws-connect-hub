<script>
import { mapGetters } from 'vuex';
import Auth from '../../../api/auth';
import HubDropdownItem from 'shared/components/ui/dropdown/DropdownItem.vue';
import HubDropdownMenu from 'shared/components/ui/dropdown/DropdownMenu.vue';
import AvailabilityStatus from 'dashboard/components/layout/AvailabilityStatus.vue';

export default {
  components: {
    HubDropdownMenu,
    HubDropdownItem,
    AvailabilityStatus,
  },
  props: {
    show: {
      type: Boolean,
      default: false,
    },
  },
  computed: {
    ...mapGetters({
      currentUser: 'getCurrentUser',
      globalConfig: 'globalConfig/get',
      accountId: 'getCurrentAccountId',
      isFeatureEnabledonAccount: 'accounts/isFeatureEnabledonAccount',
      currentRole: 'getCurrentRole',
    }),
    showChangeAccountOption() {
      if (this.globalConfig.createNewAccountFromDashboard) {
        return true;
      }

      const { accounts = [] } = this.currentUser;
      return accounts.length > 1;
    },
    hideProfileForAgents() {     
      return (
        this.currentRole !== 'administrator' &&
        this.isFeatureEnabledonAccount(
          this.accountId,
          'hide_profile_for_agent'
        )
      );
    },
  },
  methods: {
    handleProfileSettingClick(e, navigate) {
      this.$emit('close');
      navigate(e);
    },
    handleKeyboardHelpClick() {
      this.$emit('openKeyShortcutModal');
      this.$emit('close');
    },
    logout() {
      Auth.logout();
    },
    onClickAway() {
      if (this.show) this.$emit('close');
    },
    openAppearanceOptions() {
      const commandPalette = document.querySelector('hub-command-palette');
      commandPalette.open({ parent: 'appearance_settings' });
    },
  },
};
</script>

<template>
  <transition name="menu-slide">
    <div
      v-if="show"
      v-on-clickaway="onClickAway"
      class="absolute z-30 w-64 px-2 py-2 bg-white border rounded-md shadow-xl left-3 rtl:left-auto rtl:right-3 bottom-16 dark:bg-slate-800 border-slate-25 dark:border-slate-700"
      :class="{ 'block visible': show }"
    >
      <AvailabilityStatus />
      <HubDropdownMenu>
        <HubDropdownItem v-if="showChangeAccountOption">
          <hub-button
            variant="clear"
            color-scheme="secondary"
            size="small"
            icon="arrow-swap"
            @click="$emit('toggleAccounts')"
          >
            {{ $t('SIDEBAR_ITEMS.CHANGE_ACCOUNTS') }}
          </hub-button>
        </HubDropdownItem>
        <HubDropdownItem v-if="globalConfig.hubInboxToken">
          <hub-button
            variant="clear"
            color-scheme="secondary"
            size="small"
            icon="chat-help"
            @click="$emit('showSupportChatWindow')"
          >
            {{ $t('SIDEBAR_ITEMS.CONTACT_SUPPORT') }}
          </hub-button>
        </HubDropdownItem>
        <HubDropdownItem>
          <hub-button
            variant="clear"
            color-scheme="secondary"
            size="small"
            icon="keyboard"
            @click="handleKeyboardHelpClick"
          >
            {{ $t('SIDEBAR_ITEMS.KEYBOARD_SHORTCUTS') }}
          </hub-button>
        </HubDropdownItem>
        <HubDropdownItem v-if="!hideProfileForAgents">
          <router-link
            v-slot="{ href, isActive, navigate }"
            :to="`/app/accounts/${accountId}/profile/settings`"
            custom
          >
            <a
              :href="href"
              class="h-8 bg-white button small clear secondary dark:bg-slate-800"
              :class="{ 'is-active': isActive }"
              @click="e => handleProfileSettingClick(e, navigate)"
            >
              <fluent-icon icon="person" size="14" class="icon icon--font" />
              <span class="button__content">
                {{ $t('SIDEBAR_ITEMS.PROFILE_SETTINGS') }}
              </span>
            </a>
          </router-link>
        </HubDropdownItem>
        <HubDropdownItem>
          <hub-button
            variant="clear"
            color-scheme="secondary"
            size="small"
            icon="appearance"
            @click="openAppearanceOptions"
          >
            {{ $t('SIDEBAR_ITEMS.APPEARANCE') }}
          </hub-button>
        </HubDropdownItem>
        <HubDropdownItem v-if="currentUser.type === 'SuperAdmin'">
          <a
            href="/super_admin"
            class="h-8 bg-white button small clear secondary dark:bg-slate-800"
            target="_blank"
            rel="noopener nofollow noreferrer"
            @click="$emit('close')"
          >
            <fluent-icon
              icon="content-settings"
              size="14"
              class="icon icon--font"
            />
            <span class="button__content">
              {{ $t('SIDEBAR_ITEMS.SUPER_ADMIN_CONSOLE') }}
            </span>
          </a>
        </HubDropdownItem>
        <HubDropdownItem>
          <hub-button
            variant="clear"
            color-scheme="secondary"
            size="small"
            icon="power"
            @click="logout"
          >
            {{ $t('SIDEBAR_ITEMS.LOGOUT') }}
          </hub-button>
        </HubDropdownItem>
      </HubDropdownMenu>
    </div>
  </transition>
</template>
