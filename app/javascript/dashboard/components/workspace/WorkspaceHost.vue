<script>
import WorkspaceFrame from './WorkspaceFrame.vue';
import { workspaceScope } from 'dashboard/helper/workspaceApps.mjs';

export default {
  components: { WorkspaceFrame },
  data() { return { timer: null, pendingAction: null, top: 0 }; },
  computed: {
    workspace() { return this.$store.state.workspaceApps; },
    accountId() { return Number(this.$store.getters.getCurrentAccountId) || null; },
    userId() { return this.$store.getters.isLoggedIn ? this.$store.getters.getCurrentUser?.id : null; },
    scope() { return workspaceScope(this.accountId, this.userId); },
    tabCount() { return this.workspace.tabs.length; },
    activeId() { return this.workspace.activeId; },
    isRTL() { return this.$store.getters['accounts/isRTL']; },
  },
  watch: {
    scope: { immediate: true, handler() {
      this.pendingAction = null;
      this.$store.commit('workspaceApps/reset', { accountId: this.accountId, userId: this.userId });
      this.$store.dispatch('workspaceApps/refresh');
    } },
    '$route.fullPath'() { this.pendingAction = null; this.$store.commit('workspaceApps/deactivate'); },
    tabCount() { this.updateTimer(); },
    activeId() { this.$nextTick(() => this.measureTop()); },
  },
  mounted() {
    window.addEventListener('focus', this.refresh);
    window.addEventListener('resize', this.measureTop);
    this.updateTimer();
  },
  beforeDestroy() {
    clearInterval(this.timer);
    window.removeEventListener('focus', this.refresh);
    window.removeEventListener('resize', this.measureTop);
    this.$store.commit('workspaceApps/reset');
  },
  methods: {
    refresh() { if (this.tabCount) this.$store.dispatch('workspaceApps/refresh'); },
    updateTimer() { clearInterval(this.timer); this.timer = this.tabCount ? setInterval(this.refresh, 60000) : null; },
    measureTop() { this.top = Math.max(0, document.querySelector('[data-workspace-primary]')?.getBoundingClientRect().top || 0); },
    confirmAction(value) { this.pendingAction = value; },
    performAction() {
      if (!this.pendingAction) return;
      const { action, id } = this.pendingAction;
      this.$store.commit(`workspaceApps/${action}`, id);
      this.pendingAction = null;
    },
  },
};
</script>

<template>
  <div v-show="!!activeId" class="workspace-host" :class="{ 'workspace-host--rtl': isRTL }" :style="{ top: `${top}px` }">
    <!-- Never put this host inside a router-view or key frames by the active route. -->
    <WorkspaceFrame
      v-for="tab in workspace.tabs"
      v-show="tab.id === activeId"
      :key="tab.key"
      :app="tab.app"
      :account-id="workspace.accountId"
      @confirmAction="confirmAction"
    />
    <hub-modal :show="!!pendingAction" :on-close="() => { pendingAction = null; }">
      <div class="workspace-host__confirm">
        <h2>{{ $t('WORKSPACE_APPS.CONFIRM_TITLE') }}</h2>
        <p>{{ $t('WORKSPACE_APPS.CONFIRM_MESSAGE') }}</p>
        <div class="workspace-host__actions">
          <hub-button type="button" variant="hollow" @click="pendingAction = null">{{ $t('WORKSPACE_APPS.CANCEL') }}</hub-button>
          <hub-button type="button" @click="performAction">{{ $t('WORKSPACE_APPS.CONFIRM') }}</hub-button>
        </div>
      </div>
    </hub-modal>
  </div>
</template>

<style scoped>
.workspace-host { position: fixed; z-index: 35; left: 4rem; right: 0; bottom: 0; min-width: 0; background: white; }
.workspace-host--rtl { left: 0; right: 4rem; }
.workspace-host__confirm { padding: 1.5rem; }
.workspace-host__confirm h2 { font-size: 1.15rem; }
.workspace-host__actions { display: flex; justify-content: flex-end; gap: .75rem; }
</style>
