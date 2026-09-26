<script>
import WorkspaceFrame from './WorkspaceFrame.vue';
import { workspaceScope } from 'dashboard/helper/workspaceApps.mjs';
import { menuPosition } from 'dashboard/helper/workspacePresentation.mjs';

export default {
  components: { WorkspaceFrame },
  props: { available: { type: Boolean, default: true } },
  data() { return { timer: null, bounds: { top: '0px', left: '4rem', right: '0px', bottom: '0px' }, menuBounds: {} }; },
  computed: {
    workspace() { return this.$store.state.workspaceApps; },
    accountId() { return Number(this.$store.getters.getCurrentAccountId) || null; },
    userId() { return this.$store.getters.isLoggedIn ? this.$store.getters.getCurrentUser?.id : null; },
    scope() { return workspaceScope(this.accountId, this.userId); },
    tabCount() { return this.workspace.tabs.length; },
    activeId() { return this.workspace.activeId; },
    pendingAction() { return this.workspace.pendingAction; },
    contextMenu() { return this.workspace.contextMenu; },
    contextTab() { return this.workspace.tabs.find(tab => tab.id === this.contextMenu?.id); },
    isRTL() { return this.$store.getters['accounts/isRTL']; },
  },
  watch: {
    scope: { immediate: true, handler() {
      this.$store.commit('workspaceApps/reset', { accountId: this.accountId, userId: this.userId });
      this.$store.dispatch('workspaceApps/refresh');
    } },
    '$route.fullPath'() { this.$store.commit('workspaceApps/deactivate'); this.$nextTick(this.measureBounds); },
    tabCount() { this.updateTimer(); },
    activeId() { this.$nextTick(this.measureBounds); },
    available() { this.$nextTick(this.measureBounds); },
    contextMenu(value) {
      if (!value) return;
      this.menuBounds = menuPosition(value.x, value.y, window.innerWidth, window.innerHeight);
      this.$nextTick(() => this.$refs.menu?.querySelector('button')?.focus());
    },
  },
  mounted() {
    window.addEventListener('focus', this.refresh);
    window.addEventListener('online', this.refresh);
    window.addEventListener('resize', this.measureBounds);
    window.addEventListener('blur', this.closeContext);
    document.addEventListener('pointerdown', this.outsideContext);
    document.addEventListener('keydown', this.onEscape);
    if (typeof ResizeObserver !== 'undefined') {
      this.observer = new ResizeObserver(this.measureBounds);
      this.observer.observe(document.body);
    }
    this.$nextTick(this.measureBounds);
    this.updateTimer();
  },
  beforeDestroy() {
    clearInterval(this.timer);
    this.observer?.disconnect();
    window.removeEventListener('focus', this.refresh);
    window.removeEventListener('online', this.refresh);
    window.removeEventListener('resize', this.measureBounds);
    window.removeEventListener('blur', this.closeContext);
    document.removeEventListener('pointerdown', this.outsideContext);
    document.removeEventListener('keydown', this.onEscape);
    this.$store.commit('workspaceApps/reset');
  },
  methods: {
    refresh() { if (this.tabCount || this.workspace.failed || !this.workspace.sessionRestored) this.$store.dispatch('workspaceApps/refresh'); },
    updateTimer() { clearInterval(this.timer); this.timer = this.tabCount ? setInterval(this.refresh, 60000) : null; },
    measureBounds() {
      const primary = document.querySelector('[data-workspace-primary]');
      if (!primary) return;
      if (this.observedPrimary !== primary) {
        if (this.observedPrimary) this.observer?.unobserve(this.observedPrimary);
        this.observedPrimary = primary;
        this.observer?.observe(primary);
      }
      const rect = primary.getBoundingClientRect();
      this.bounds = {
        top: `${Math.max(0, rect.top)}px`, bottom: `${Math.max(0, window.innerHeight - rect.bottom)}px`,
        left: this.isRTL ? '0px' : `${Math.max(0, rect.right)}px`,
        right: this.isRTL ? `${Math.max(0, window.innerWidth - rect.left)}px` : '0px',
      };
    },
    confirmAction(value) { this.$store.commit('workspaceApps/requestAction', value); },
    performAction() {
      if (!this.pendingAction) return;
      const { action, id } = this.pendingAction;
      this.$store.commit(`workspaceApps/${action}`, id);
      this.confirmAction(null);
    },
    closeContext() { this.$store.commit('workspaceApps/context', null); },
    outsideContext(event) { if (this.contextMenu && !this.$refs.menu?.contains(event.target)) this.closeContext(); },
    onEscape(event) {
      if (event.key !== 'Escape' || !this.contextMenu) return;
      const id = this.contextMenu.id;
      this.closeContext();
      document.querySelector(`[data-workspace-tab="${id}"]`)?.focus();
    },
    menuKey(event) {
      const entries = [...this.$refs.menu.querySelectorAll('button, a')];
      const index = entries.indexOf(document.activeElement);
      if (!['ArrowDown', 'ArrowUp', 'Home', 'End'].includes(event.key)) return;
      event.preventDefault();
      const next = event.key === 'Home' ? 0 : event.key === 'End' ? entries.length - 1 : (index + (event.key === 'ArrowDown' ? 1 : -1) + entries.length) % entries.length;
      entries[next]?.focus();
    },
  },
};
</script>

<template>
  <div class="workspace-shell">
    <!-- Content plane only: native menus (30), hints (40) and global dialogs stay above it. -->
    <div v-show="available && !!activeId" class="workspace-host" :style="bounds">
      <!-- Kept outside router-view; v-show never recreates an application on route changes. -->
      <WorkspaceFrame v-for="tab in workspace.tabs" v-show="tab.id === activeId" :key="tab.key" :app="tab.app" :active="available && tab.id === activeId" :account-id="workspace.accountId" :scope="scope" @confirmAction="confirmAction" />
    </div>
    <!-- Dialogs and context menus are siblings, not prisoners of the content stacking context. -->
    <div v-if="contextMenu && contextTab" ref="menu" class="workspace-context" :style="menuBounds" role="menu" :aria-label="contextTab.app.name" @keydown="menuKey">
      <button type="button" role="menuitem" @click="confirmAction({ action: 'close', id: contextTab.id })">{{ $t('WORKSPACE_APPS.CLOSE_APP') }}</button>
      <button type="button" role="menuitem" @click="confirmAction({ action: 'closeOthers', id: contextTab.id })">{{ $t('WORKSPACE_APPS.CLOSE_OTHERS') }}</button>
      <button type="button" role="menuitem" @click="confirmAction({ action: 'reload', id: contextTab.id })">{{ $t('WORKSPACE_APPS.RELOAD') }}</button>
      <a role="menuitem" :href="contextTab.app.url" target="_blank" rel="noopener noreferrer" referrerpolicy="no-referrer" @click="closeContext">{{ $t('WORKSPACE_APPS.OPEN_EXTERNAL') }}</a>
    </div>
    <hub-modal :show="!!pendingAction" :on-close="() => confirmAction(null)">
      <div class="workspace-host__confirm">
        <h2>{{ $t('WORKSPACE_APPS.CONFIRM_TITLE') }}</h2>
        <p>{{ $t('WORKSPACE_APPS.CONFIRM_MESSAGE') }}</p>
        <div class="workspace-host__actions">
          <hub-button type="button" variant="hollow" @click="confirmAction(null)">{{ $t('WORKSPACE_APPS.CANCEL') }}</hub-button>
          <hub-button type="button" @click="performAction">{{ $t('WORKSPACE_APPS.CONFIRM') }}</hub-button>
        </div>
      </div>
    </hub-modal>
  </div>
</template>

<style scoped>
.workspace-host { position: fixed; z-index: var(--z-index-low, 10); min-width: 0; background: white; }
.workspace-context { position: fixed; z-index: 40; width: 224px; padding: .4rem; border: 1px solid #e2e8f0; border-radius: .5rem; background: white; box-shadow: 0 8px 24px rgb(15 23 42 / .14); }
.workspace-context button, .workspace-context a { display: block; width: 100%; padding: .6rem; border: 0; border-radius: .3rem; background: transparent; color: #334155; font-size: .85rem; text-align: start; cursor: pointer; }
.workspace-context button:hover, .workspace-context a:hover, .workspace-context :focus-visible { background: #eff6ff; outline: 1px solid #bfdbfe; }
.workspace-host__confirm { padding: 1.5rem; }
.workspace-host__confirm h2 { font-size: 1.15rem; }
.workspace-host__actions { display: flex; justify-content: flex-end; gap: .75rem; }
.dark .workspace-context { background: #0f172a; border-color: #334155; }
.dark .workspace-context button, .dark .workspace-context a { color: #e2e8f0; }
.dark .workspace-context button:hover, .dark .workspace-context a:hover { background: #1e293b; }
</style>

<style>
.tooltip.workspace-tooltip {
  pointer-events: none !important;
  max-width: min(22rem, calc(100vw - 5rem));
  overflow-wrap: anywhere;
  white-space: normal;
}
</style>
