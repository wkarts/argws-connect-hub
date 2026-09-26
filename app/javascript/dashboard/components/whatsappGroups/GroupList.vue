<script>
import api from 'dashboard/api/whatsappGroups';
import { GROUP_EVENT, groupFailure, groupDestination } from 'dashboard/helper/whatsappGroups.mjs';
import { BUS_EVENTS } from 'shared/constants/busEvents';
export default {
  props: { inboxId: { type: [Number, String], default: 0 }, active: Boolean },
  data() { return { rows: [], total: 0, page: 1, query: '', loading: false, error: '', sequence: 0, timer: null }; },
  computed: { accountId() { return this.$store.getters.getCurrentAccountId; }, scope() { return `${this.accountId}:${this.inboxId}`; }, pages() { return Math.max(1, Math.ceil(this.total / 25)); } },
  watch: { scope: { immediate: true, handler() { this.sequence += 1; this.rows = []; this.total = 0; this.load(1); } }, active(value) { if (value) this.scheduleRefresh(); } },
  mounted() {
    this.$emitter.on(GROUP_EVENT, this.changed); this.$emitter.on(BUS_EVENTS.WEBSOCKET_RECONNECT, this.scheduleRefresh);
    window.addEventListener('focus', this.scheduleRefresh); window.addEventListener('online', this.scheduleRefresh);
  },
  beforeDestroy() {
    this.sequence += 1; clearTimeout(this.timer); this.$emitter.off(GROUP_EVENT, this.changed);
    this.$emitter.off(BUS_EVENTS.WEBSOCKET_RECONNECT, this.scheduleRefresh);
    window.removeEventListener('focus', this.scheduleRefresh); window.removeEventListener('online', this.scheduleRefresh);
  },
  methods: {
    changed(event) {
      if (Number(event.account_id) !== Number(this.accountId) || (this.inboxId && Number(event.inbox_id) !== Number(this.inboxId))) return;
      if (event.invalidated) { this.sequence += 1; this.rows = this.rows.filter(group => event.group_id ? Number(group.id) !== Number(event.group_id) : Number(group.inbox_id) !== Number(event.inbox_id)); }
      if (!this.active && !event.invalidated && this.rows.some(group => Number(group.id) === Number(event.group_id))) return;
      this.scheduleRefresh();
    },
    scheduleRefresh() { clearTimeout(this.timer); this.timer = setTimeout(() => this.load(), 200); },
    async load(page = this.page) {
      const sequence = ++this.sequence; this.loading = true; this.error = '';
      try {
        const { data } = await api.list(this.accountId, { ...(this.inboxId ? { inbox_id: this.inboxId } : {}), page, q: this.query });
        if (sequence !== this.sequence) return;
        this.rows = data.groups; this.total = data.total; this.page = data.page;
        this.$emit('count', this.total);
      } catch (error) { if (sequence === this.sequence) { this.error = groupFailure(error, this.$t('GROUP_MANAGEMENT.ERROR')); if ([401, 403, 404].includes(error?.response?.status)) this.rows = []; } }
      finally { if (sequence === this.sequence) this.loading = false; }
    },
    open(group, history = false) { this.$router.push(groupDestination(this.accountId, group, history)).catch(() => {}); },
    async toggleMute(group) {
      const scope = this.scope;
      try { const { data } = await api.preference(this.accountId, group.id, { muted: !group.muted }); if (scope === this.scope) this.$set(group, 'muted', data.muted); }
      catch (error) { if (scope === this.scope) this.error = groupFailure(error, this.$t('GROUP_MANAGEMENT.ERROR')); }
    },
  },
};
</script>
<template>
  <section class="flex min-h-0 flex-1 flex-col" :aria-label="$t('GROUP_MANAGEMENT.TITLE')">
    <form class="flex gap-1 p-3" @submit.prevent="load(1)">
      <input v-model="query" maxlength="120" class="mb-0 min-w-0 text-sm" :placeholder="$t('GROUP_MANAGEMENT.SEARCH')" :aria-label="$t('GROUP_MANAGEMENT.SEARCH')" />
      <hub-button type="submit" icon="search" variant="clear" size="small" :disabled="loading" :title="$t('GROUP_MANAGEMENT.SEARCH_BUTTON')" />
    </form>
    <p v-if="error" role="alert" class="px-3 text-xs text-red-600">{{ error }}</p>
    <p v-if="loading" role="status" class="px-3 text-xs text-slate-500">{{ $t('GROUP_MANAGEMENT.LOADING') }}</p>
    <p v-if="!loading && !rows.length" class="px-3 text-sm text-slate-500">{{ $t('GROUP_MANAGEMENT.EMPTY') }}</p>
    <div class="group-list-scroll min-h-0 flex-1 overflow-y-auto" tabindex="0">
      <article v-for="group in rows" :key="group.id" class="border-b border-slate-100 px-3 py-3 dark:border-slate-800">
        <div class="flex items-center gap-2">
          <button type="button" class="flex min-w-0 flex-1 items-center gap-2 text-left" @click="open(group)">
            <fluent-icon icon="people" size="24" class="flex-shrink-0" />
            <span class="min-w-0 flex-1"><strong class="block truncate text-sm font-medium" :title="group.name">{{ group.name }}</strong><span class="block text-xs text-slate-500">{{ $t(group.treatment === 'management' ? 'GROUP_MANAGEMENT.MODE_MANAGEMENT' : 'GROUP_MANAGEMENT.MODE_CONVERSATION') }}</span></span>
            <span v-if="group.unread_count" class="rounded bg-slate-100 px-1 text-xs dark:bg-slate-800">{{ group.unread_count > 99 ? '99+' : group.unread_count }}</span>
          </button>
          <hub-button size="small" variant="clear" :icon="group.muted ? 'speaker-mute' : 'speaker-1'" :title="$t(group.muted ? 'GROUP_MANAGEMENT.UNMUTE' : 'GROUP_MANAGEMENT.MUTE')" @click="toggleMute(group)" />
        </div>
        <button v-if="group.treatment === 'conversation' && group.has_management_history" type="button" class="mt-1 text-xs text-slate-500" @click="open(group, true)">{{ $t('GROUP_MANAGEMENT.MANAGEMENT_HISTORY') }}</button>
      </article>
    </div>
    <div class="flex items-center justify-between gap-1 px-3 py-2 text-xs">
      <hub-button size="small" variant="clear" :disabled="page <= 1 || loading" @click="load(page - 1)">{{ $t('GROUP_MANAGEMENT.PREVIOUS') }}</hub-button>
      <span>{{ page }} / {{ pages }}</span>
      <hub-button size="small" variant="clear" :disabled="page >= pages || loading" @click="load(page + 1)">{{ $t('GROUP_MANAGEMENT.NEXT') }}</hub-button>
    </div>
  </section>
</template>
<style scoped>
.group-list-scroll { scrollbar-width: none; }
.group-list-scroll::-webkit-scrollbar { display: none; }
</style>
