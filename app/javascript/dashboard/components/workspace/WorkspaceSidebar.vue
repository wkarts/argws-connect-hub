<script>
import WorkspaceIcon from './WorkspaceIcon.vue';
import WorkspaceRail from './WorkspaceRail.vue';
import { workspaceTooltip } from 'dashboard/helper/workspacePresentation.mjs';
import { useAlert } from 'dashboard/composables';

export default {
  components: { WorkspaceIcon, WorkspaceRail },
  computed: {
    workspace() { return this.$store.state.workspaceApps; },
  },
  methods: {
    hint(name) { return workspaceTooltip(name, this.$store.getters['accounts/isRTL']); },
    context(event, id) {
      const rect = event.currentTarget.getBoundingClientRect();
      this.$store.commit('workspaceApps/context', { id, x: event.clientX || rect.right, y: event.clientY || rect.top });
    },
    toggleLauncher() {
      this.$store.commit('workspaceApps/launcher', !this.workspace.launcherOpen);
      if (this.workspace.launcherOpen) this.$store.dispatch('workspaceApps/refresh');
    },
    async select(id) {
      try { await this.$store.dispatch('workspaceApps/open', id); }
      catch (_) { useAlert(this.$t('WORKSPACE_APPS.UNAVAILABLE')); }
    },
  },
};
</script>

<template>
  <div class="workspace-sidebar">
    <button
      v-tooltip="hint($t('WORKSPACE_APPS.TITLE'))"
      data-workspace-toggle
      type="button"
      class="workspace-sidebar__button"
      :class="{ 'is-active': workspace.launcherOpen }"
      :aria-label="$t('WORKSPACE_APPS.TITLE')"
      :aria-expanded="workspace.launcherOpen ? 'true' : 'false'"
      aria-controls="hub-workspace-launcher"
      @click.stop="toggleLauncher"
    >
      <svg width="22" height="22" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.5" aria-hidden="true">
        <rect x="3.5" y="3.5" width="6.5" height="6.5" rx="1.5" />
        <rect x="14" y="3.5" width="6.5" height="6.5" rx="1.5" />
        <rect x="3.5" y="14" width="6.5" height="6.5" rx="1.5" />
        <rect x="14" y="14" width="6.5" height="6.5" rx="1.5" />
      </svg>
    </button>
    <WorkspaceRail v-if="workspace.tabs.length" class="workspace-sidebar__tabs" :label="$t('WORKSPACE_APPS.OPEN_APPS')" :active-id="workspace.activeId">
      <button
        v-for="tab in workspace.tabs"
        :key="tab.id"
        v-tooltip="hint(tab.app.name)"
        type="button"
        class="workspace-sidebar__button workspace-sidebar__tab"
        :data-workspace-tab="tab.id"
        :class="{ 'is-active': workspace.activeId === tab.id }"
        :aria-label="tab.app.name"
        :aria-pressed="workspace.activeId === tab.id ? 'true' : 'false'"
        @click="select(tab.id)"
        @contextmenu.prevent.stop="context($event, tab.id)"
        @keydown.shift.f10.prevent="context($event, tab.id)"
      >
        <WorkspaceIcon :app="tab.app" />
        <span class="workspace-sidebar__dot" aria-hidden="true" />
      </button>
    </WorkspaceRail>
  </div>
</template>

<style scoped>
.workspace-sidebar { display: flex; flex-direction: column; align-items: center; min-height: 0; flex: 1; width: 100%; }
.workspace-sidebar__button { display: flex; position: relative; align-items: center; justify-content: center; width: 2.5rem; height: 2.5rem; min-height: 2.5rem; margin: .5rem auto; border: 0; border-radius: .5rem; background: transparent; color: #475569; cursor: pointer; }
.workspace-sidebar__button:hover { background: #f1f5f9; }
.workspace-sidebar__button:focus-visible { outline: 2px solid #3b82f6; outline-offset: 2px; }
.workspace-sidebar__button.is-active { background: #eff6ff; color: #2563eb; }
.workspace-sidebar__tabs { width: 100%; min-height: 0; border-top: 1px solid #e2e8f0; }
.workspace-sidebar__dot { width: 4px; height: 4px; border-radius: 50%; background: currentColor; position: absolute; bottom: 2px; }
.dark .workspace-sidebar__button { color: #cbd5e1; }
.dark .workspace-sidebar__button:hover, .dark .workspace-sidebar__button.is-active { background: #1e293b; }
.dark .workspace-sidebar__tabs { border-color: #334155; }
</style>
