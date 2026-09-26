<script>
import WorkspaceIcon from './WorkspaceIcon.vue';
import { toolbarPreference, workspaceTooltip } from 'dashboard/helper/workspacePresentation.mjs';

export default {
  components: { WorkspaceIcon },
  props: {
    app: { type: Object, required: true }, scope: { type: String, default: '' },
    active: { type: Boolean, default: true }, forceVisible: { type: Boolean, default: false },
    navigation: { type: Object, default: () => ({ ready: false, back: false, forward: false }) },
  },
  data() { return { pinned: false, visible: true }; },
  computed: { shown() { return this.active && (this.pinned || this.visible || this.forceVisible); } },
  watch: {
    active(value) { clearTimeout(this.hideTimer); this.visible = value; if (value) this.scheduleHide(1200); },
  },
  mounted() { this.pinned = toolbarPreference(this.scope); this.$emit('pin', this.pinned); this.scheduleHide(1600); },
  beforeDestroy() { clearTimeout(this.hideTimer); },
  methods: {
    hint(key) { return { ...workspaceTooltip(this.$t(`WORKSPACE_APPS.${key}`)), placement: 'bottom' }; },
    reveal() { clearTimeout(this.hideTimer); this.visible = true; },
    scheduleHide(delay = 200) {
      clearTimeout(this.hideTimer);
      this.hideTimer = setTimeout(() => {
        if (!this.$refs.header?.contains(document.activeElement)) this.visible = false;
      }, delay);
    },
    leaveFocus(event) { if (!this.$el.contains(event.relatedTarget)) this.scheduleHide(); },
    togglePin() {
      this.pinned = !this.pinned;
      toolbarPreference(this.scope, this.pinned);
      this.$emit('pin', this.pinned);
      if (!this.pinned) this.scheduleHide();
    },
    hide(event) {
      if (event.key !== 'Escape' || this.pinned || this.forceVisible) return;
      event.preventDefault(); this.$refs.handle.focus(); this.visible = false;
    },
  },
};
</script>

<template>
  <div class="workspace-toolbar" :class="{ 'is-shown': shown, 'is-pinned': pinned }" @keydown="hide">
    <button ref="handle" type="button" class="workspace-toolbar__handle" :aria-label="$t('WORKSPACE_APPS.SHOW_TOOLBAR')" :aria-expanded="shown ? 'true' : 'false'" @mouseenter="reveal" @focus="reveal" @click="reveal"><span /></button>
    <header ref="header" class="workspace-toolbar__header" @mouseenter="reveal" @mouseleave="scheduleHide()" @focusin="reveal" @focusout="leaveFocus">
      <button v-tooltip="hint('BACK_TO_HUB')" type="button" class="workspace-toolbar__action" :aria-label="$t('WORKSPACE_APPS.BACK_TO_HUB')" @click="$emit('hub')"><fluent-icon icon="chat-multiple" size="18" /></button>
      <span v-tooltip="hint(navigation.ready ? 'NAV_BACK' : 'NAV_UNAVAILABLE')" class="workspace-toolbar__control">
        <button type="button" class="workspace-toolbar__action" :disabled="!navigation.ready || !navigation.back" :aria-label="$t('WORKSPACE_APPS.NAV_BACK')" @click="$emit('navigate', 'back')"><fluent-icon icon="chevron-left" size="18" /></button>
      </span>
      <span v-tooltip="hint(navigation.ready ? 'NAV_FORWARD' : 'NAV_UNAVAILABLE')" class="workspace-toolbar__control">
        <button type="button" class="workspace-toolbar__action" :disabled="!navigation.ready || !navigation.forward" :aria-label="$t('WORKSPACE_APPS.NAV_FORWARD')" @click="$emit('navigate', 'forward')"><fluent-icon icon="chevron-right" size="18" /></button>
      </span>
      <WorkspaceIcon :app="app" :size="28" />
      <span class="workspace-toolbar__name" :title="app.name">{{ app.name }}</span>
      <button v-if="app.auth_mode === 'form_post'" v-tooltip="hint('MY_LOGIN')" type="button" class="workspace-toolbar__action" :aria-label="$t('WORKSPACE_APPS.MY_LOGIN')" @click="$emit('login')"><fluent-icon icon="key" size="18" /></button>
      <button v-tooltip="hint('DIAGNOSE')" type="button" class="workspace-toolbar__action" :aria-label="$t('WORKSPACE_APPS.DIAGNOSE')" @click="$emit('diagnose')"><fluent-icon icon="info" size="18" /></button>
      <button v-tooltip="hint('RELOAD')" type="button" class="workspace-toolbar__action" :aria-label="$t('WORKSPACE_APPS.RELOAD')" @click="$emit('reload')"><fluent-icon icon="arrow-clockwise" size="18" /></button>
      <a v-tooltip="hint('OPEN_EXTERNAL')" :href="app.url" target="_blank" rel="noopener noreferrer" referrerpolicy="no-referrer" class="workspace-toolbar__action" :aria-label="$t('WORKSPACE_APPS.OPEN_EXTERNAL')"><fluent-icon icon="open" size="18" /></a>
      <button v-tooltip="hint(pinned ? 'UNPIN_TOOLBAR' : 'PIN_TOOLBAR')" type="button" class="workspace-toolbar__action" :aria-label="$t(pinned ? 'WORKSPACE_APPS.UNPIN_TOOLBAR' : 'WORKSPACE_APPS.PIN_TOOLBAR')" :aria-pressed="pinned ? 'true' : 'false'" @click="togglePin"><svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.6" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><path d="m16 3 5 5-3 1-3 5v3l-3-3-5 3-2-2 3-5-3-3h3l5-3 1-3" /><path d="m8 16-5 5" /></svg></button>
      <button v-tooltip="hint('CLOSE_APP')" type="button" class="workspace-toolbar__action" :aria-label="$t('WORKSPACE_APPS.CLOSE_APP')" @click="$emit('close')"><fluent-icon icon="dismiss" size="18" /></button>
    </header>
  </div>
</template>

<style scoped>
.workspace-toolbar { position: absolute; inset: 0 0 auto; z-index: 3; pointer-events: none; }
.workspace-toolbar__header { display: flex; align-items: center; gap: 3px; height: 38px; padding: 0 6px; border-bottom: 1px solid #e2e8f0; background: #fff; transform: translateY(-100%); visibility: hidden; pointer-events: none; transition: transform 120ms ease, visibility 120ms; }
.workspace-toolbar.is-shown .workspace-toolbar__header { transform: translateY(0); visibility: visible; pointer-events: auto; }
.workspace-toolbar__handle { position: absolute; inset-block-start: 0; inset-inline-end: 12px; padding: 0; width: 40px; height: 10px; display: flex; align-items: center; justify-content: center; border: 0; border-radius: 0 0 5px 5px; background: #f1f5f9; color: #64748b; cursor: pointer; pointer-events: auto; }
.workspace-toolbar__handle span { width: 20px; height: 2px; border-radius: 2px; background: currentColor; }
.workspace-toolbar.is-shown .workspace-toolbar__handle { opacity: 0; }
.workspace-toolbar__name { flex: 1; min-width: 0; font-size: 12px; font-weight: 500; overflow: hidden; white-space: nowrap; text-overflow: ellipsis; }
.workspace-toolbar__action { display: inline-flex; flex-shrink: 0; align-items: center; justify-content: center; width: 28px; height: 28px; padding: 0; border: 0; border-radius: 5px; color: #475569; background: transparent; cursor: pointer; }
.workspace-toolbar__action:disabled { opacity: .35; cursor: default; }
.workspace-toolbar__action:hover:not(:disabled), .workspace-toolbar__action[aria-pressed="true"] { background: #eff6ff; color: #2563eb; }
.workspace-toolbar__action:focus-visible, .workspace-toolbar__handle:focus-visible { outline: 2px solid #3b82f6; outline-offset: -2px; }
.workspace-toolbar__control { display: inline-flex; flex-shrink: 0; }
.dark .workspace-toolbar__header { background: #0f172a; color: #e2e8f0; border-color: #334155; }
.dark .workspace-toolbar__action { color: #cbd5e1; }
.dark .workspace-toolbar__action:hover:not(:disabled), .dark .workspace-toolbar__handle { background: #1e293b; color: #e2e8f0; }
@media (max-width: 480px) { .workspace-toolbar__header { gap: 0; padding: 0 2px; } .workspace-toolbar__name { display: none; } .workspace-toolbar__action { width: 26px; } }
@media (prefers-reduced-motion: reduce) { .workspace-toolbar__header { transition: none; } }
</style>
