<script>
import WorkspaceIcon from './WorkspaceIcon.vue';
import { useAlert } from 'dashboard/composables';
import { safeApplicationUrl } from 'dashboard/helper/workspaceApps.mjs';

export default {
  components: { WorkspaceIcon },
  computed: {
    workspace() { return this.$store.state.workspaceApps; },
    isAdmin() { return this.$store.getters.getCurrentRole === 'administrator'; },
    settingsPath() { return `/app/accounts/${this.workspace.accountId}/settings/workspace-apps`; },
  },
  mounted() {
    document.addEventListener('click', this.onOutsideClick);
    document.addEventListener('keydown', this.onEscape);
    this.$nextTick(() => this.$refs.closeButton?.focus());
  },
  beforeDestroy() {
    document.removeEventListener('click', this.onOutsideClick);
    document.removeEventListener('keydown', this.onEscape);
  },
  methods: {
    close() {
      this.$store.commit('workspaceApps/launcher', false);
      document.querySelector('[data-workspace-toggle]')?.focus();
    },
    onOutsideClick(event) { if (!this.$el.contains(event.target)) this.close(); },
    onEscape(event) { if (event.key === 'Escape') this.close(); },
    async open(app) {
      if (app.launch_mode === 'external') {
        if (safeApplicationUrl(app.url, window.location.origin)) window.open(app.url, '_blank', 'noopener,noreferrer');
        this.close();
        return;
      }
      try { await this.$store.dispatch('workspaceApps/open', app.id); }
      catch (_) { useAlert(this.$t('WORKSPACE_APPS.UNAVAILABLE')); }
    },
  },
};
</script>

<template>
  <nav id="hub-workspace-launcher" class="workspace-launcher" :aria-label="$t('WORKSPACE_APPS.TITLE')">
    <button ref="closeButton" type="button" class="workspace-launcher__item" :aria-label="$t('WORKSPACE_APPS.CLOSE_CATALOG')" @click="close">
      <fluent-icon icon="dismiss" size="20" />
    </button>
    <div class="workspace-launcher__items" :aria-busy="workspace.loading ? 'true' : 'false'">
      <button
        v-for="app in workspace.apps"
        :key="app.id"
        v-tooltip.right="app.name"
        type="button"
        class="workspace-launcher__item"
        :aria-label="app.name"
        @click="open(app)"
      >
        <WorkspaceIcon :app="app" />
      </button>
      <button v-if="workspace.failed" v-tooltip.right="$t('WORKSPACE_APPS.RETRY')" type="button" class="workspace-launcher__item" :aria-label="$t('WORKSPACE_APPS.RETRY')" @click="$store.dispatch('workspaceApps/refresh')">
        <fluent-icon icon="arrow-clockwise" size="20" />
      </button>
      <div v-if="!workspace.apps.length && !workspace.loading && !workspace.failed" v-tooltip.right="$t('WORKSPACE_APPS.EMPTY')" class="workspace-launcher__item" tabindex="0" :aria-label="$t('WORKSPACE_APPS.EMPTY')">
        <fluent-icon icon="globe" size="20" />
      </div>
    </div>
    <router-link v-if="isAdmin" v-tooltip.right="$t('WORKSPACE_APPS.MANAGE')" :to="settingsPath" class="workspace-launcher__item" :aria-label="$t('WORKSPACE_APPS.MANAGE')" @click.native="close">
      <fluent-icon icon="settings" size="20" />
    </router-link>
  </nav>
</template>

<style scoped>
.workspace-launcher { position: absolute; z-index: 90; inset-block: 0; inset-inline-start: 4rem; display: flex; flex-direction: column; align-items: center; width: 4rem; background: white; border-inline-end: 1px solid #e2e8f0; box-shadow: 8px 0 24px rgb(15 23 42 / .08); padding: .5rem 0; }
.workspace-launcher__items { flex: 1; width: 100%; min-height: 0; overflow-y: auto; scrollbar-width: thin; }
.workspace-launcher__item { display: flex; align-items: center; justify-content: center; width: 2.5rem; height: 2.5rem; margin: .5rem auto; border: 0; border-radius: .5rem; background: transparent; color: #475569; cursor: pointer; }
.workspace-launcher__item:hover { background: #eff6ff; color: #2563eb; }
.workspace-launcher__item:focus-visible { outline: 2px solid #3b82f6; outline-offset: 2px; }
.dark .workspace-launcher { background: #0f172a; border-color: #334155; }
.dark .workspace-launcher__item { color: #cbd5e1; }
.dark .workspace-launcher__item:hover { background: #1e293b; }
</style>
