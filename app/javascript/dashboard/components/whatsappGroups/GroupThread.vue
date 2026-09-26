<script>
import api from 'dashboard/api/whatsappGroups';
import { GROUP_EVENT, groupFailure, groupDestination, mergeGroupMessages } from 'dashboard/helper/whatsappGroups.mjs';
import { BUS_EVENTS } from 'shared/constants/busEvents';
import GroupConfirm from './GroupConfirm.vue';
export default {
  components: { GroupConfirm },
  props: { groupId: { type: [String, Number], required: true } },
  data() { return { group: null, messages: [], nextBefore: null, legacy: false, text: '', file: null, reply: null, loading: false,
    sending: false, error: '', sequence: 0, accessEpoch: 0, sendRequestId: 0, timer: null, confirmRequest: null, pendingClient: null, messageRequests: {}, alive: true }; },
  computed: {
    accountId() { return this.$store.getters.getCurrentAccountId; }, scope() { return `${this.accountId}:${this.groupId}`; },
    canSend() { return this.group?.treatment === 'management' && this.group.can_reply && !this.legacy; },
  },
  watch: { scope: { immediate: true, handler() { this.sequence += 1; this.accessEpoch += 1; this.sendRequestId += 1; this.sending = false; this.group = null; this.messages = []; this.nextBefore = null; this.text = ''; this.file = null; this.reply = null; this.legacy = false; this.pendingClient = null; this.messageRequests = {}; this.finishConfirmation(false); this.refresh(); } } },
  mounted() {
    this.$emitter.on(GROUP_EVENT, this.changed); this.$emitter.on(BUS_EVENTS.WEBSOCKET_RECONNECT, this.scheduleRefresh);
    window.addEventListener('focus', this.scheduleRefresh); window.addEventListener('online', this.scheduleRefresh);
    document.addEventListener('visibilitychange', this.visible);
  },
  beforeDestroy() {
    this.alive = false; this.sequence += 1; clearTimeout(this.timer); this.finishConfirmation(false);
    this.$emitter.off(GROUP_EVENT, this.changed); this.$emitter.off(BUS_EVENTS.WEBSOCKET_RECONNECT, this.scheduleRefresh);
    window.removeEventListener('focus', this.scheduleRefresh); window.removeEventListener('online', this.scheduleRefresh);
    document.removeEventListener('visibilitychange', this.visible);
  },
  methods: {
    changed(event) {
      if (Number(event.account_id) !== Number(this.accountId) || (event.group_id && Number(event.group_id) !== Number(this.groupId))) return;
      if (this.group && Number(event.inbox_id) !== Number(this.group.inbox_id)) return;
      if (event.invalidated) { this.sequence += 1; this.accessEpoch += 1; this.group = null; this.messages = []; this.nextBefore = null; this.text = ''; this.file = null; this.reply = null; this.pendingClient = null; this.finishConfirmation(false); }
      if (!event.invalidated && event.message_id && !this.legacy && this.group) { this.syncMessage(event.message_id); return; }
      this.scheduleRefresh();
    },
    visible() { if (!document.hidden) this.scheduleRefresh(); },
    scheduleRefresh() { clearTimeout(this.timer); this.timer = setTimeout(() => this.refresh(), 150); },
    async refresh(older = false) {
      if (!this.alive) return;
      const sequence = ++this.sequence; const account = this.accountId; const id = this.groupId; const legacy = this.legacy;
      const oldScroll = this.$refs.messages?.scrollHeight || 0;
      const nearBottom = !this.$refs.messages || this.$refs.messages.scrollHeight - this.$refs.messages.scrollTop - this.$refs.messages.clientHeight < 100;
      this.loading = true; this.error = '';
      try {
        const [{ data: group }, { data }] = await Promise.all([api.show(account, id), api.messages(account, id, older ? { before: this.nextBefore } : {}, legacy)]);
        if (sequence !== this.sequence || !this.alive) return;
        this.group = group;
        const previousIds = new Set(this.messages.map(message => message.id));
        const gap = !older && previousIds.size > 0 && data.messages.length > 0 && !data.messages.some(message => previousIds.has(message.id));
        this.messages = mergeGroupMessages(gap ? [] : this.messages, data.messages);
        if (gap || older || this.nextBefore === null) this.nextBefore = data.next_before;
        await this.$nextTick();
        if (this.$refs.messages) {
          if (older) this.$refs.messages.scrollTop += this.$refs.messages.scrollHeight - oldScroll;
          else if (nearBottom) this.$refs.messages.scrollTop = this.$refs.messages.scrollHeight;
        }
        if (!legacy && !document.hidden && nearBottom && !older && data.messages.length) {
          api.preference(account, id, { read: true, last_message_id: data.messages[data.messages.length - 1].id }).catch(() => {});
        }
      } catch (error) {
        if (sequence !== this.sequence || !this.alive) return;
        if ([401, 403, 404].includes(error?.response?.status)) { this.accessEpoch += 1; this.group = null; this.messages = []; this.nextBefore = null; this.text = ''; this.file = null; this.reply = null; this.pendingClient = null; this.error = this.$t('GROUP_MANAGEMENT.UNAVAILABLE'); }
        else this.error = groupFailure(error, this.$t('GROUP_MANAGEMENT.ERROR'));
      } finally { if (sequence === this.sequence) this.loading = false; }
    },
    async syncMessage(id) {
      const scope = this.scope; const epoch = this.sequence;
      const nearBottom = !this.$refs.messages || this.$refs.messages.scrollHeight - this.$refs.messages.scrollTop - this.$refs.messages.clientHeight < 100;
      const version = (this.messageRequests[id] || 0) + 1; this.messageRequests[id] = version;
      try {
        const { data } = await api.message(this.accountId, this.groupId, id);
        if (!this.alive || scope !== this.scope || epoch !== this.sequence || this.legacy || this.messageRequests[id] !== version) return;
        this.messages = mergeGroupMessages(this.messages, [data]);
        await this.$nextTick();
        if (nearBottom && this.$refs.messages) this.$refs.messages.scrollTop = this.$refs.messages.scrollHeight;
        if (!document.hidden && nearBottom) api.preference(this.accountId, this.groupId, { read: true, last_message_id: id }).catch(() => {});
      } catch (error) {
        if (!this.alive || scope !== this.scope || epoch !== this.sequence) return;
        if ([401, 403, 404].includes(error?.response?.status)) { this.sequence += 1; this.accessEpoch += 1; this.group = null; this.messages = []; this.nextBefore = null; this.text = ''; this.file = null; this.reply = null; this.pendingClient = null; this.finishConfirmation(false); }
        this.scheduleRefresh();
      }
    },
    async history(legacy) { this.legacy = legacy; this.messages = []; this.nextBefore = null; this.reply = null; await this.refresh(); },
    chooseFile(event) {
      const file = event.target.files?.[0]; event.target.value = '';
      if (file && file.size > 25 * 1024 * 1024) { this.error = this.$t('GROUP_MANAGEMENT.FILE_LIMIT'); return; }
      this.file = file || null;
    },
    async send() {
      if (!this.canSend || this.sending || (!this.text.trim() && !this.file)) return;
      const account = this.accountId; const id = this.groupId; const scope = this.scope;
      const accessEpoch = this.accessEpoch; const requestId = ++this.sendRequestId;
      const fingerprint = JSON.stringify([this.text, this.file?.name, this.file?.size, this.file?.lastModified, this.reply?.source_id]);
      if (!this.pendingClient || this.pendingClient.fingerprint !== fingerprint) {
        const bytes = new Uint8Array(16); window.crypto.getRandomValues(bytes);
        this.pendingClient = { fingerprint, id: [...bytes].map(value => value.toString(16).padStart(2, '0')).join('').replace(/^(........)(....)(....)(....)(............)$/, '$1-$2-$3-$4-$5') };
      }
      const data = new FormData(); data.append('group_message[client_id]', this.pendingClient.id); data.append('group_message[content]', this.text);
      if (this.file) data.append('group_message[file]', this.file);
      if (this.reply) data.append('group_message[reply_to_source_id]', this.reply.source_id);
      this.sending = true; this.error = '';
      try {
        const { data: message } = await api.send(account, id, data);
        if (scope !== this.scope || !this.alive || accessEpoch !== this.accessEpoch || requestId !== this.sendRequestId) return;
        if (this.legacy) { this.pendingClient = null; return; }
        this.messages = mergeGroupMessages(this.messages, [message]); this.text = ''; this.file = null; this.reply = null; this.pendingClient = null;
        await this.refresh();
      } catch (error) { if (scope === this.scope && this.alive && accessEpoch === this.accessEpoch && requestId === this.sendRequestId) this.error = groupFailure(error, this.$t('GROUP_MANAGEMENT.STATUS_UNCERTAIN')); }
      finally { if (requestId === this.sendRequestId) this.sending = false; }
    },
    async toggleMute() {
      if (!this.group) return; const scope = this.scope;
      try { const { data } = await api.preference(this.accountId, this.groupId, { muted: !this.group.muted }); if (scope === this.scope && this.group) this.group.muted = data.muted; }
      catch (error) { if (scope === this.scope) this.error = groupFailure(error, this.$t('GROUP_MANAGEMENT.ERROR')); }
    },
    confirm(message) { return new Promise(resolve => { this.confirmRequest = { message, resolve }; }); },
    finishConfirmation(value) { const request = this.confirmRequest; this.confirmRequest = null; request?.resolve(value); },
    async revoke(message) {
      const scope = this.scope; if (!(await this.confirm(this.$t('GROUP_MANAGEMENT.REVOKE_CONFIRM')))) return;
      if (scope !== this.scope) return;
      try { await api.revoke(this.accountId, this.groupId, message.id); if (scope === this.scope) this.messages = this.messages.map(row => row.id === message.id ? { ...row, content: null, files: [], deleted_at: new Date().toISOString(), can_revoke: false } : row); await this.refresh(); }
      catch (error) { if (scope === this.scope) this.error = groupFailure(error, this.$t('GROUP_MANAGEMENT.ERROR')); }
    },
    async cancelPending(message) {
      const scope = this.scope; if (!(await this.confirm(this.$t('GROUP_MANAGEMENT.CANCEL_PENDING_CONFIRM')))) return;
      if (scope !== this.scope) return;
      try { await api.cancel(this.accountId, this.groupId, message.id); await this.refresh(); }
      catch (error) { if (scope === this.scope) this.error = groupFailure(error, this.$t('GROUP_MANAGEMENT.ERROR')); }
    },
    back() { this.$router.push({ name: 'inbox_dashboard', params: { accountId: this.accountId, inbox_id: this.group?.inbox_id || this.$route.params.inbox_id }, query: { groupTab: '1' } }).catch(() => {}); },
    openTicket() { if (this.group?.conversation_id) this.$router.push(groupDestination(this.accountId, this.group)).catch(() => {}); },
    timestamp(value) { const date = new Date(value); return Number.isNaN(date.getTime()) ? '' : date.toLocaleString(this.$i18n?.locale === 'pt_BR' ? 'pt-BR' : 'en'); },
    isImage(file) { return /^image\/(png|jpeg|webp|gif)$/.test(file.content_type); },
  },
};
</script>
<template>
  <section class="group-thread flex min-w-0 flex-1 flex-col bg-white dark:bg-slate-900" :aria-label="$t('GROUP_MANAGEMENT.TITLE')">
    <header class="flex flex-shrink-0 items-center gap-2 border-b border-slate-100 px-4 py-3 dark:border-slate-800">
      <hub-button icon="arrow-left" size="small" variant="clear" :title="$t('GROUP_MANAGEMENT.BACK')" @click="back" />
      <fluent-icon icon="people" size="24" />
      <div class="min-w-0 flex-1"><h2 class="mb-0 truncate text-sm font-semibold">{{ group ? group.name : $t('GROUP_MANAGEMENT.TITLE') }}</h2><span v-if="group" class="text-xs text-slate-500">{{ $t(group.treatment === 'management' ? 'GROUP_MANAGEMENT.MODE_MANAGEMENT' : 'GROUP_MANAGEMENT.MODE_CONVERSATION') }}</span></div>
      <hub-button v-if="group" :icon="group.muted ? 'speaker-mute' : 'speaker-1'" size="small" variant="clear" :title="$t(group.muted ? 'GROUP_MANAGEMENT.UNMUTE' : 'GROUP_MANAGEMENT.MUTE')" @click="toggleMute" />
      <hub-button icon="arrow-clockwise" size="small" variant="clear" :disabled="loading" :title="$t('GROUP_MANAGEMENT.RELOAD')" @click="refresh(false)" />
    </header>
    <div v-if="group" class="flex flex-wrap items-center gap-2 px-4 py-2 text-xs text-slate-500">
      <button v-if="group.has_legacy_history" type="button" :class="{ 'font-semibold': legacy }" @click="history(true)">{{ $t('GROUP_MANAGEMENT.LEGACY_HISTORY') }}</button>
      <button v-if="legacy" type="button" @click="history(false)">{{ $t('GROUP_MANAGEMENT.MANAGEMENT_HISTORY') }}</button>
      <button v-if="group.treatment === 'conversation' && group.conversation_id" type="button" @click="openTicket">{{ $t('GROUP_MANAGEMENT.OPEN_TICKET') }}</button>
    </div>
    <p v-if="error" role="alert" class="px-4 text-sm text-red-600">{{ error }}</p>
    <p v-if="loading" role="status" class="px-4 text-xs text-slate-500">{{ $t('GROUP_MANAGEMENT.LOADING') }}</p>
    <p v-if="group && !canSend" class="px-4 text-xs text-slate-500">{{ $t(group.treatment === 'conversation' && !group.conversation_id && !group.has_management_history ? 'GROUP_MANAGEMENT.NO_TICKET' : 'GROUP_MANAGEMENT.READ_ONLY') }}</p>
    <div ref="messages" class="min-h-0 flex-1 overflow-y-auto px-4 py-3" aria-live="polite" aria-relevant="additions text">
      <div v-if="nextBefore" class="mb-3 text-center"><hub-button size="small" variant="clear" :disabled="loading" @click="refresh(true)">{{ $t('GROUP_MANAGEMENT.OLDER') }}</hub-button></div>
      <p v-if="group && !loading && !messages.length" class="text-center text-sm text-slate-500">{{ $t('GROUP_MANAGEMENT.NO_MESSAGES') }}</p>
      <article v-for="message in messages" :key="`${legacy}:${message.id}`" class="group-message mb-3 rounded-lg border border-slate-100 p-3 dark:border-slate-800" :class="{ 'group-message-outgoing': message.direction === 'outgoing' }">
        <div class="mb-1 flex flex-wrap items-center justify-between gap-2 text-xs text-slate-500"><strong>{{ message.user_name || message.sender_name || message.sender_jid || group.name }}</strong><time>{{ timestamp(message.sent_at) }}</time></div>
        <p v-if="message.deleted_at" class="mb-0 text-sm italic text-slate-500">{{ $t('GROUP_MANAGEMENT.DELETED') }}</p>
        <template v-else>
          <p v-if="message.reply_to_source_id" class="mb-1 truncate text-xs text-slate-500">↪ {{ message.reply_to_source_id }}</p>
          <p v-if="message.content" class="mb-1 whitespace-pre-wrap break-words text-sm">{{ message.content }}</p>
          <div v-for="attachment in message.files" :key="attachment.id" class="mt-2">
            <a v-if="isImage(attachment)" :href="attachment.url" target="_blank" rel="noopener noreferrer"><img :src="attachment.url" :alt="attachment.name" class="max-h-64 max-w-full rounded object-contain" loading="lazy" /></a>
            <audio v-else-if="(attachment.content_type || '').startsWith('audio/')" :src="attachment.url" controls preload="none" class="max-w-full" />
            <video v-else-if="(attachment.content_type || '').startsWith('video/')" :src="attachment.url" controls preload="none" class="max-h-64 max-w-full" />
            <a v-else :href="attachment.url" target="_blank" rel="noopener noreferrer" class="break-all text-sm underline">{{ attachment.name }}</a>
          </div>
          <span v-if="['image', 'audio', 'video', 'document', 'sticker'].includes(message.kind) && !message.files.length" class="text-xs text-slate-500">{{ $t('GROUP_MANAGEMENT.WAITING_FILE') }}</span>
          <div class="mt-2 flex flex-wrap items-center justify-end gap-3 text-xs text-slate-500">
            <span>{{ $t(`GROUP_MANAGEMENT.STATUS_${message.status.toUpperCase()}`) }}</span>
            <button v-if="canSend && message.source_id" type="button" @click="reply = message">{{ $t('GROUP_MANAGEMENT.REPLY') }}</button>
            <button v-if="!legacy && message.can_revoke" type="button" @click="revoke(message)">{{ $t('GROUP_MANAGEMENT.REVOKE') }}</button>
            <button v-if="!legacy && message.can_cancel" type="button" @click="cancelPending(message)">{{ $t('GROUP_MANAGEMENT.CANCEL_PENDING') }}</button>
          </div>
        </template>
      </article>
    </div>
    <form v-if="canSend" class="flex-shrink-0 border-t border-slate-100 p-3 dark:border-slate-800" @submit.prevent="send">
      <div v-if="reply" class="mb-2 flex items-center justify-between gap-2 text-xs text-slate-500"><span class="truncate">{{ $t('GROUP_MANAGEMENT.SELECTED_REPLY', { name: reply.sender_name || reply.user_name || reply.sender_jid || group.name }) }}</span><button type="button" :disabled="sending" @click="reply = null">{{ $t('GROUP_MANAGEMENT.CANCEL') }}</button></div>
      <div v-if="file" class="mb-2 flex items-center justify-between gap-2 text-xs"><span class="truncate">{{ file.name }}</span><button type="button" :disabled="sending" @click="file = null">{{ $t('GROUP_MANAGEMENT.REMOVE_FILE') }}</button></div>
      <textarea v-model="text" maxlength="65536" rows="3" :disabled="sending" :placeholder="$t('GROUP_MANAGEMENT.MESSAGE')" :aria-label="$t('GROUP_MANAGEMENT.MESSAGE')" class="mb-2 resize-y" @keydown.ctrl.enter.prevent="send" />
      <div class="flex items-center justify-between gap-2"><label class="mb-0 cursor-pointer text-sm">{{ $t('GROUP_MANAGEMENT.ATTACH') }}<input type="file" class="sr-only" :disabled="sending" :aria-label="$t('GROUP_MANAGEMENT.UPLOAD_FILE')" @change="chooseFile" /></label><hub-button type="submit" :disabled="sending || (!text.trim() && !file)">{{ $t('GROUP_MANAGEMENT.SEND') }}</hub-button></div>
    </form>
    <GroupConfirm v-if="confirmRequest" :message="confirmRequest.message" @confirm="finishConfirmation(true)" @cancel="finishConfirmation(false)" />
  </section>
</template>
<style scoped>
.group-message { max-width: min(85%, 680px); overflow-wrap: anywhere; }
.group-message-outgoing { margin-left: auto; background: rgba(128, 128, 128, 0.06); }
@media(max-width: 600px) { .group-message { max-width: 96%; } }
</style>
