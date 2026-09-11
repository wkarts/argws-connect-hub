<script>
import { mapGetters } from 'vuex';
import router from '../dashboard/routes';
import AddAccountModal from '../dashboard/components/layout/sidebarComponents/AddAccountModal.vue';
import LoadingState from './components/widgets/LoadingState.vue';
import NetworkNotification from './components/NetworkNotification.vue';
import UpdateBanner from './components/app/UpdateBanner.vue';
import UpgradeBanner from './components/app/UpgradeBanner.vue';
import PaymentPendingBanner from './components/app/PaymentPendingBanner.vue';
import PendingEmailVerificationBanner from './components/app/PendingEmailVerificationBanner.vue';
import vueActionCable from './helper/actionCable';
import HubSnackbarBox from './components/SnackbarContainer.vue';
import { setColorTheme } from './helper/themeHelper';
import { isOnOnboardingView } from 'v3/helpers/RouteHelper';
import {
  registerSubscription,
  verifyServiceWorkerExistence,
} from './helper/pushHelper';
import ReconnectService from 'dashboard/helper/ReconnectService';

export default {
  name: 'App',

  components: {
    AddAccountModal,
    LoadingState,
    NetworkNotification,
    UpdateBanner,
    PaymentPendingBanner,
    HubSnackbarBox,
    UpgradeBanner,
    PendingEmailVerificationBanner,
  },
  data() {
    return {
      showAddAccountModal: false,
      latestHubVersion: null,
      reconnectService: null,
    };
  },

  computed: {
    ...mapGetters({
      getAccount: 'accounts/getAccount',
      isRTL: 'accounts/isRTL',
      currentUser: 'getCurrentUser',
      authUIFlags: 'getAuthUIFlags',
      accountUIFlags: 'accounts/getUIFlags',
      currentAccountId: 'getCurrentAccountId',
    }),
    hasAccounts() {
      const { accounts = [] } = this.currentUser || {};
      return accounts.length > 0;
    },
    hideOnOnboardingView() {
      return !isOnOnboardingView(this.$route);
    },
  },

  watch: {
    currentUser() {
      if (!this.hasAccounts) {
        this.showAddAccountModal = true;
      }
    },
    currentAccountId() {
      if (this.currentAccountId) {
        this.initializeAccount();
      }
    },
  },
  mounted() {
    this.initializeColorTheme();
    this.listenToThemeChanges();
    this.setLocale(window.hubConfig.selectedLocale);
  },
  beforeDestroy() {
    if (this.reconnectService) {
      this.reconnectService.disconnect();
    }
  },
  methods: {
    initializeColorTheme() {
      setColorTheme(window.matchMedia('(prefers-color-scheme: dark)').matches);
    },
    listenToThemeChanges() {
      const mql = window.matchMedia('(prefers-color-scheme: dark)');
      mql.onchange = e => setColorTheme(e.matches);
    },
    setLocale(locale) {
      this.$root.$i18n.locale = locale;
    },
    async initializeAccount() {
      await this.$store.dispatch('accounts/get');
      this.$store.dispatch('setActiveAccount', {
        accountId: this.currentAccountId,
      });
      const { locale, latest_hub_version: latestHubVersion } =
        this.getAccount(this.currentAccountId);
      const { pubsub_token: pubsubToken } = this.currentUser || {};
      this.setLocale(locale);
      this.latestHubVersion = latestHubVersion;
      vueActionCable.init(pubsubToken);
      this.reconnectService = new ReconnectService(this.$store, router);

      verifyServiceWorkerExistence(registration =>
        registration.pushManager.getSubscription().then(subscription => {
          if (subscription) {
            registerSubscription();
          }
        })
      );
    },
  },
};
</script>

<template>
  <div
    v-if="!authUIFlags.isFetching && !accountUIFlags.isFetchingItem"
    id="app"
    class="flex-grow-0 w-full h-full min-h-0 app-wrapper"
    :class="{ 'app-rtl--wrapper': isRTL }"
    :dir="isRTL ? 'rtl' : 'ltr'"
  >
    <UpdateBanner :latest-hub-version="latestHubVersion" />
    <template v-if="currentAccountId">
      <PendingEmailVerificationBanner v-if="hideOnOnboardingView" />
      <PaymentPendingBanner v-if="hideOnOnboardingView" />
      <UpgradeBanner />
    </template>
    <transition name="fade" mode="out-in">
      <router-view />
    </transition>
    <AddAccountModal :show="showAddAccountModal" :has-accounts="hasAccounts" />
    <HubSnackbarBox />
    <NetworkNotification />
  </div>
  <LoadingState v-else />
</template>

<style lang="scss">
@import './assets/scss/app';

/* Chamada: mantém a ação de microfone claramente identificável como botão. */
#app .fixed.inset-0.z-50 .mt-4.flex.flex-wrap.items-center.gap-2 > .flex-1.justify-center {
  background-color: #ffffff;
  border: 1px solid #cbd5e1;
  color: #334155;
  box-shadow: 0 1px 2px rgb(15 23 42 / 0.06);
}

#app .fixed.inset-0.z-50 .mt-4.flex.flex-wrap.items-center.gap-2 > .flex-1.justify-center:hover {
  background-color: #f1f5f9;
  border-color: #94a3b8;
  color: #0f172a;
}

.dark #app .fixed.inset-0.z-50 .mt-4.flex.flex-wrap.items-center.gap-2 > .flex-1.justify-center {
  background-color: #334155;
  border-color: #64748b;
  color: #f8fafc;
}

.dark #app .fixed.inset-0.z-50 .mt-4.flex.flex-wrap.items-center.gap-2 > .flex-1.justify-center:hover {
  background-color: #475569;
  border-color: #94a3b8;
}
</style>

<style src="vue-multiselect/dist/vue-multiselect.min.css"></style>
