<script>
import api from 'dashboard/api/whatsappGroups';
import { groupFailure } from 'dashboard/helper/whatsappGroups.mjs';
import GroupConfirm from 'dashboard/components/whatsappGroups/GroupConfirm.vue';
export default {
  components: { GroupConfirm },
  props: { inbox: { type: Object, required: true } },
  data() {
    return { loaded: false, loading: false, busy: false, error: '', notice: '', settings: null, enabled: false,
      groups: [], users: [], page: 1, total: 0, query: '', edit: null, selectedIds: [], bulkMode: '', bulkSelection: '', confirmRequest: null, sequence: 0 };
  },
  computed: {
    accountId() { return this.$store.getters.getCurrentAccountId; },
    scope() { return `${this.accountId}:${this.inbox.id}`; },
    pages() { return Math.max(1, Math.ceil(this.total / 25)); },
  },
  watch: { scope: { immediate: true, handler() { this.sequence += 1; this.loaded = false; this.edit = null; this.groups = []; this.load(1); } } },
  beforeDestroy() { this.sequence += 1; this.finishConfirmation(false); },
  methods: {
    async load(page = this.page, refreshGeneral = false) {
      const sequence = ++this.sequence; const account = this.accountId; const inbox = this.inbox.id;
      this.loading = true; this.error = '';
      try {
        const { data } = await api.settings(account, inbox, { page, q: this.query });
        if (sequence !== this.sequence) return;
        if (!this.loaded || refreshGeneral) {
          this.settings = { ...data.settings, default_user_ids: [...data.settings.default_user_ids] };
          this.enabled = data.enabled;
        } this.users = data.users; this.groups = data.groups;
        this.page = data.page; this.total = data.total; this.selectedIds = []; this.loaded = true;
      } catch (error) { if (sequence === this.sequence) this.error = groupFailure(error, this.$t('GROUP_MANAGEMENT.ERROR')); }
      finally { if (sequence === this.sequence) this.loading = false; }
    },
    async perform(action, refreshGeneral = false) {
      if (this.busy) return;
      const scope = this.scope; this.busy = true; this.error = ''; this.notice = '';
      try {
        await action();
        if (scope !== this.scope) return;
        this.edit = null; this.notice = this.$t('GROUP_MANAGEMENT.SAVED');
        await this.load(this.page, refreshGeneral); this.$store.dispatch('inboxes/get');
      } catch (error) { if (scope === this.scope) this.error = groupFailure(error, this.$t('GROUP_MANAGEMENT.ERROR')); }
      finally { this.busy = false; }
    },
    confirm(message) { return new Promise(resolve => { this.confirmRequest = { message, resolve }; }); },
    finishConfirmation(value) { const request = this.confirmRequest; this.confirmRequest = null; request?.resolve(value); },
    saveSettings() {
      const account = this.accountId; const inbox = this.inbox.id;
      const data = { settings: { ...this.settings }, enabled: this.enabled };
      this.perform(() => api.saveSettings(account, inbox, data), true);
    },
    sync() { const account = this.accountId; const inbox = this.inbox.id; this.perform(() => api.sync(account, inbox)); },
    editGroup(group) { this.edit = { ...group, allowed_user_ids: [...group.allowed_user_ids], originalTreatment: group.treatment }; },
    async saveGroup() {
      const edit = this.edit; if (!edit) return;
      const scope = this.scope; const changed = edit.treatment !== edit.originalTreatment;
      if (changed && !(await this.confirm(this.$t('GROUP_MANAGEMENT.TRANSITION_HELP')))) return;
      if (scope !== this.scope) return;
      const { selected, treatment, access_mode, allowed_user_ids, lock_version } = edit;
      const account = this.accountId; const inbox = this.inbox.id;
      this.perform(() => api.saveGroup(account, inbox, edit.id, { group: { selected, treatment, access_mode, allowed_user_ids, lock_version }, confirmed: changed }));
    },
    async applyBulk() {
      const rows = this.groups.filter(group => this.selectedIds.includes(group.id));
      if (!rows.length || (!this.bulkMode && !this.bulkSelection)) return;
      const scope = this.scope;
      if (!(await this.confirm(this.$t('GROUP_MANAGEMENT.BULK_CONFIRM', { count: rows.length })))) return;
      if (scope !== this.scope) return;
      const groups = rows.map(group => ({ id: group.id, lock_version: group.lock_version,
        ...(this.bulkMode ? { treatment: this.bulkMode } : {}), ...(this.bulkSelection ? { selected: this.bulkSelection === 'yes' } : {}) }));
      const account = this.accountId; const inbox = this.inbox.id;
      this.perform(() => api.bulk(account, inbox, { groups, confirmed: true }));
    },
    async replay(group) {
      const scope = this.scope;
      if (!(await this.confirm(this.$t('GROUP_MANAGEMENT.REPLAY_HELP')))) return;
      if (scope !== this.scope) return;
      const account = this.accountId; const inbox = this.inbox.id;
      this.perform(() => api.replay(account, inbox, group.id));
    },
    mode(value) { return this.$t(`GROUP_MANAGEMENT.MODE_${value.toUpperCase()}`); },
  },
};
</script>
<template>
  <section class="group-settings mx-8 py-4">
    <h2 class="text-base font-semibold">{{ $t('GROUP_MANAGEMENT.TITLE') }}</h2>
    <p class="text-sm text-slate-500">{{ $t('GROUP_MANAGEMENT.INTRO') }}</p>
    <p v-if="error" role="alert" class="my-3 text-sm text-red-600">{{ error }}</p>
    <p v-if="notice" role="status" class="my-3 text-sm text-green-600">{{ notice }}</p>
    <p v-if="loading && !loaded" role="status">{{ $t('GROUP_MANAGEMENT.LOADING') }}</p>
    <hub-button v-if="!loaded && !loading" @click="load(1)">{{ $t('GROUP_MANAGEMENT.RELOAD') }}</hub-button>
    <template v-if="loaded">
      <form class="rounded-lg border border-slate-200 p-4 dark:border-slate-700" @submit.prevent="saveSettings">
        <fieldset :disabled="busy || loading">
          <label class="flex items-center gap-2"><input v-model="enabled" type="checkbox" />{{ $t('GROUP_MANAGEMENT.ENABLED') }}</label>
          <p class="text-xs text-slate-500">{{ $t('GROUP_MANAGEMENT.ENABLED_HELP') }}</p>
          <div class="group-settings-grid">
            <label>{{ $t('GROUP_MANAGEMENT.SELECTION') }}
              <select v-model="settings.selection_mode"><option value="all">{{ $t('GROUP_MANAGEMENT.ALL_GROUPS') }}</option><option value="selected">{{ $t('GROUP_MANAGEMENT.SELECTED_GROUPS') }}</option></select>
            </label>
            <label>{{ $t('GROUP_MANAGEMENT.DEFAULT_MODE') }}
              <select v-model="settings.default_treatment"><option value="conversation">{{ mode('conversation') }}</option><option value="management">{{ mode('management') }}</option></select>
            </label>
            <label>{{ $t('GROUP_MANAGEMENT.DEFAULT_ACCESS') }}
              <select v-model="settings.default_access_mode"><option value="inbox">{{ $t('GROUP_MANAGEMENT.INHERIT') }}</option><option value="selected">{{ $t('GROUP_MANAGEMENT.SELECTED_USERS') }}</option></select>
            </label>
            <div v-if="settings.default_access_mode === 'selected'" class="group-user-selector" role="group" :aria-label="$t('GROUP_MANAGEMENT.USERS')"><strong class="text-xs">{{ $t('GROUP_MANAGEMENT.USERS') }}</strong><label v-for="user in users" :key="user.id"><input v-model="settings.default_user_ids" type="checkbox" :value="user.id" />{{ user.name }}</label></div>
          </div>
          <p class="text-xs text-slate-500">{{ $t('GROUP_MANAGEMENT.DEFAULT_HELP') }}</p>
          <hub-button type="submit" :disabled="busy || loading">{{ $t('GROUP_MANAGEMENT.SAVE_GENERAL') }}</hub-button>
        </fieldset>
      </form>
      <div class="my-4 flex flex-wrap items-center gap-2">
        <form class="flex min-w-0 flex-1 gap-2" @submit.prevent="load(1)">
          <input v-model="query" maxlength="120" :placeholder="$t('GROUP_MANAGEMENT.SEARCH')" :aria-label="$t('GROUP_MANAGEMENT.SEARCH')" class="mb-0 min-w-0" />
          <hub-button type="submit" variant="clear" :disabled="loading || busy">{{ $t('GROUP_MANAGEMENT.SEARCH_BUTTON') }}</hub-button>
        </form>
        <hub-button variant="smooth" :disabled="loading || busy" @click="sync">{{ $t('GROUP_MANAGEMENT.SYNC') }}</hub-button>
      </div>
      <div v-if="selectedIds.length" class="mb-3 flex flex-wrap items-center gap-2 text-sm">
        <span>{{ $t('GROUP_MANAGEMENT.SELECTED_COUNT', { count: selectedIds.length }) }}</span>
        <select v-model="bulkMode" :aria-label="$t('GROUP_MANAGEMENT.MODE')"><option value="">{{ $t('GROUP_MANAGEMENT.KEEP_MODE') }}</option><option value="conversation">{{ mode('conversation') }}</option><option value="management">{{ mode('management') }}</option></select>
        <select v-model="bulkSelection" :aria-label="$t('GROUP_MANAGEMENT.FOLLOW')"><option value="">{{ $t('GROUP_MANAGEMENT.KEEP_SELECTION') }}</option><option value="yes">{{ $t('GROUP_MANAGEMENT.FOLLOW') }}</option><option value="no">{{ $t('GROUP_MANAGEMENT.UNFOLLOW') }}</option></select>
        <hub-button :disabled="busy || loading || (!bulkMode && !bulkSelection)" @click="applyBulk">{{ $t('GROUP_MANAGEMENT.APPLY') }}</hub-button>
      </div>
      <p v-if="!groups.length" class="py-4 text-sm text-slate-500">{{ $t('GROUP_MANAGEMENT.EMPTY_ADMIN') }}</p>
      <div v-for="group in groups" :key="group.id" class="group-settings-row border-b border-slate-100 py-3 dark:border-slate-800">
        <input v-model="selectedIds" type="checkbox" :value="group.id" :disabled="busy" :aria-label="$t('GROUP_MANAGEMENT.SELECT_GROUP', { name: group.name })" />
        <div class="min-w-0 flex-1"><strong class="block truncate text-sm" :title="group.name">{{ group.name }}</strong><span class="block truncate text-xs text-slate-500">{{ group.jid }}</span></div>
        <span class="text-xs">{{ mode(group.treatment) }}</span>
        <span class="text-xs text-slate-500">{{ $t(group.access_mode === 'inbox' ? 'GROUP_MANAGEMENT.INHERIT_SHORT' : 'GROUP_MANAGEMENT.RESTRICTED') }}</span>
        <span class="text-xs">{{ $t(settings.selection_mode === 'all' || group.selected ? 'GROUP_MANAGEMENT.FOLLOWING' : 'GROUP_MANAGEMENT.NOT_FOLLOWING') }}</span>
        <hub-button size="small" variant="clear" :disabled="busy" @click="editGroup(group)">{{ $t('GROUP_MANAGEMENT.CONFIGURE') }}</hub-button>
      </div>
      <div class="mt-3 flex items-center justify-end gap-3 text-sm">
        <hub-button size="small" variant="clear" :disabled="page <= 1 || busy || loading" @click="load(page - 1)">{{ $t('GROUP_MANAGEMENT.PREVIOUS') }}</hub-button>
        <span>{{ page }} / {{ pages }}</span>
        <hub-button size="small" variant="clear" :disabled="page >= pages || busy || loading" @click="load(page + 1)">{{ $t('GROUP_MANAGEMENT.NEXT') }}</hub-button>
      </div>
      <form v-if="edit" class="mt-5 rounded-lg border border-slate-200 p-4 dark:border-slate-700" @submit.prevent="saveGroup">
        <h3 class="text-sm font-semibold">{{ edit.name }}</h3>
        <fieldset :disabled="busy">
          <label class="flex items-center gap-2"><input v-model="edit.selected" type="checkbox" />{{ $t('GROUP_MANAGEMENT.FOLLOW_IN_SELECTION') }}</label>
          <div class="group-settings-grid">
            <label>{{ $t('GROUP_MANAGEMENT.MODE') }}<select v-model="edit.treatment"><option value="conversation">{{ mode('conversation') }}</option><option value="management">{{ mode('management') }}</option></select></label>
            <label>{{ $t('GROUP_MANAGEMENT.ACCESS') }}<select v-model="edit.access_mode"><option value="inbox">{{ $t('GROUP_MANAGEMENT.INHERIT') }}</option><option value="selected">{{ $t('GROUP_MANAGEMENT.SELECTED_USERS') }}</option></select></label>
            <div v-if="edit.access_mode === 'selected'" class="group-user-selector" role="group" :aria-label="$t('GROUP_MANAGEMENT.USERS')"><strong class="text-xs">{{ $t('GROUP_MANAGEMENT.USERS') }}</strong><label v-for="user in users" :key="user.id"><input v-model="edit.allowed_user_ids" type="checkbox" :value="user.id" />{{ user.name }}</label></div>
          </div>
          <p class="text-xs text-slate-500">{{ $t(edit.treatment === 'management' ? 'GROUP_MANAGEMENT.MANAGEMENT_HELP' : 'GROUP_MANAGEMENT.CONVERSATION_HELP') }}</p>
          <p v-if="edit.access_mode === 'selected'" class="text-xs text-slate-500">{{ $t('GROUP_MANAGEMENT.ACCESS_HELP') }}</p>
          <p class="text-xs text-slate-500">{{ $t('GROUP_MANAGEMENT.IMPACT', { tickets: edit.impact.active_tickets, pending: edit.impact.pending_messages }) }}</p>
          <div class="flex flex-wrap gap-2">
            <hub-button type="submit" :disabled="busy">{{ $t('GROUP_MANAGEMENT.SAVE_GROUP') }}</hub-button>
            <hub-button variant="clear" :disabled="busy" @click="edit = null">{{ $t('GROUP_MANAGEMENT.CANCEL') }}</hub-button>
            <hub-button v-if="edit.pending_events" variant="clear" :disabled="busy" @click="replay(edit)">{{ $t('GROUP_MANAGEMENT.REPLAY', { count: edit.pending_events }) }}</hub-button>
          </div>
        </fieldset>
      </form>
    </template>
    <GroupConfirm v-if="confirmRequest" :message="confirmRequest.message" @confirm="finishConfirmation(true)" @cancel="finishConfirmation(false)" />
  </section>
</template>
<style scoped>
.group-settings-grid { display: grid; grid-template-columns: repeat(auto-fit, minmax(220px, 1fr)); gap: 16px; margin: 16px 0; }
.group-settings-grid label { font-size: 13px; }
.group-settings-grid select { display: block; width: 100%; margin-top: 4px; }
.group-user-selector { max-height: 180px; overflow-y: auto; border: 1px solid #cbd5e1; border-radius: 6px; padding: 8px; }
.group-user-selector label { display: flex; align-items: center; gap: 8px; margin: 6px 0; }
.group-user-selector input { margin: 0; }
.group-settings-row { display: flex; align-items: center; gap: 12px; }
.group-settings-row input { flex-shrink: 0; margin: 0; }
.group-settings-row > span { flex-shrink: 0; }
@media(max-width: 800px) { .group-settings { margin-left: 16px; margin-right: 16px; } .group-settings-row { flex-wrap: wrap; } .group-settings-row > div { min-width: 60%; } }
</style>
