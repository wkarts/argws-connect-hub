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
    timestamp(value) {
      const date = new Date(value);
      if (Number.isNaN(date.getTime())) return '';
      const now = new Date();
      if (date.toDateString() === now.toDateString()) {
        return date.toLocaleTimeString([], { hour: '2-digit', minute: '2-digit' });
      }
      return date.toLocaleString(this.$i18n?.locale === 'pt_BR' ? 'pt-BR' : 'en', {
        day: '2-digit', month: '2-digit', hour: '2-digit', minute: '2-digit',
      });
    },
    isImage(file) { return /^image\/(png|jpeg|webp|gif)$/.test(file.content_type); },
    senderName(message) {
      return message.sender?.name || message.user_name || message.sender_name || this.$t('GROUP_MANAGEMENT.PARTICIPANT', 'Participante');
    },
    senderAvatar(message) { return message.sender?.avatar_url || ''; },
    async togglePin() {
      if (!this.group) return;
      const scope = this.scope;
      try {
        const { data } = await api.preference(this.accountId, this.groupId, { pinned: !this.group.pinned });
        if (scope === this.scope && this.group) {
          this.group.pinned = data.pinned;
          this.group.pinned_at = data.pinned_at;
        }
      } catch (error) {
        if (scope === this.scope) this.error = groupFailure(error, this.$t('GROUP_MANAGEMENT.ERROR'));
      }
    },
  },
};
</script>
<template>
  <section
    class="group-thread flex min-w-0 flex-1 flex-col bg-white dark:bg-slate-900"
    :aria-label="$t('GROUP_MANAGEMENT.TITLE')"
  >
    <header class="group-thread__header">
      <hub-button
        icon="arrow-left"
        size="small"
        variant="clear"
        :title="$t('GROUP_MANAGEMENT.BACK')"
        @click="back"
      />
      <hub-thumbnail
        v-if="group"
        :src="group.avatar_url"
        :username="group.name"
        size="36px"
      />
      <div class="min-w-0 flex-1">
        <h2 class="group-thread__title">
          {{ group ? group.name : $t('GROUP_MANAGEMENT.TITLE') }}
        </h2>
        <span v-if="group" class="group-thread__subtitle">
          {{ $t(group.treatment === 'management' ? 'GROUP_MANAGEMENT.MODE_MANAGEMENT' : 'GROUP_MANAGEMENT.MODE_CONVERSATION') }}
        </span>
      </div>
      <hub-button
        v-if="group"
        icon="pin"
        size="small"
        variant="clear"
        :class="{ 'text-blue-600': group.pinned }"
        :title="group.pinned ? 'Desafixar grupo' : 'Fixar grupo'"
        @click="togglePin"
      />
      <hub-button
        v-if="group"
        :icon="group.muted ? 'speaker-mute' : 'speaker-1'"
        size="small"
        variant="clear"
        :title="$t(group.muted ? 'GROUP_MANAGEMENT.UNMUTE' : 'GROUP_MANAGEMENT.MUTE')"
        @click="toggleMute"
      />
      <hub-button
        icon="arrow-clockwise"
        size="small"
        variant="clear"
        :disabled="loading"
        :title="$t('GROUP_MANAGEMENT.RELOAD')"
        @click="refresh(false)"
      />
    </header>

    <div v-if="group && (group.has_legacy_history || legacy || group.treatment === 'conversation')" class="group-thread__history">
      <button
        v-if="group.has_legacy_history"
        type="button"
        :class="{ 'is-active': legacy }"
        @click="history(true)"
      >
        {{ $t('GROUP_MANAGEMENT.LEGACY_HISTORY') }}
      </button>
      <button v-if="legacy" type="button" @click="history(false)">
        {{ $t('GROUP_MANAGEMENT.MANAGEMENT_HISTORY') }}
      </button>
      <button
        v-if="group.treatment === 'conversation' && group.conversation_id"
        type="button"
        @click="openTicket"
      >
        {{ $t('GROUP_MANAGEMENT.OPEN_TICKET') }}
      </button>
    </div>

    <p v-if="error" role="alert" class="px-4 py-1 text-sm text-red-600">
      {{ error }}
    </p>
    <p v-if="loading && !messages.length" role="status" class="px-4 py-2 text-xs text-slate-500">
      {{ $t('GROUP_MANAGEMENT.LOADING') }}
    </p>
    <p v-if="group && !canSend" class="px-4 py-1 text-xs text-slate-500">
      {{ $t(group.treatment === 'conversation' && !group.conversation_id && !group.has_management_history ? 'GROUP_MANAGEMENT.NO_TICKET' : 'GROUP_MANAGEMENT.READ_ONLY') }}
    </p>

    <div
      ref="messages"
      class="group-thread__messages hub-scrollbar"
      aria-live="polite"
      aria-relevant="additions text"
    >
      <div v-if="nextBefore" class="mb-4 text-center">
        <hub-button size="small" variant="clear" :disabled="loading" @click="refresh(true)">
          {{ $t('GROUP_MANAGEMENT.OLDER') }}
        </hub-button>
      </div>

      <p v-if="group && !loading && !messages.length" class="py-12 text-center text-sm text-slate-500">
        {{ $t('GROUP_MANAGEMENT.NO_MESSAGES') }}
      </p>

      <article
        v-for="message in messages"
        :key="`${legacy}:${message.id}`"
        class="group-chat-row"
        :class="{ 'group-chat-row--outgoing': message.direction === 'outgoing' }"
      >
        <div v-if="message.direction !== 'outgoing'" class="group-chat-row__avatar">
          <hub-thumbnail
            :src="senderAvatar(message)"
            :username="senderName(message)"
            size="30px"
          />
        </div>

        <div class="group-chat-row__body">
          <div
            class="group-chat-bubble"
            :class="{ 'group-chat-bubble--outgoing': message.direction === 'outgoing' }"
          >
            <div v-if="message.direction !== 'outgoing'" class="group-chat-bubble__sender">
              {{ senderName(message) }}
            </div>

            <p v-if="message.deleted_at" class="group-chat-bubble__deleted">
              {{ $t('GROUP_MANAGEMENT.DELETED') }}
            </p>

            <template v-else>
              <button
                v-if="message.reply_to_source_id"
                type="button"
                class="group-chat-bubble__reply-ref"
                disabled
              >
                ↪ {{ $t('GROUP_MANAGEMENT.REPLY') }}
              </button>

              <p v-if="message.content" class="group-chat-bubble__text">
                {{ message.content }}
              </p>

              <div
                v-for="attachment in message.files"
                :key="attachment.id"
                class="group-chat-media"
              >
                <a
                  v-if="isImage(attachment)"
                  :href="attachment.url"
                  target="_blank"
                  rel="noopener noreferrer"
                  class="group-chat-media__image-link"
                >
                  <img
                    :src="attachment.url"
                    :alt="attachment.name"
                    class="group-chat-media__image"
                    loading="lazy"
                  />
                </a>
                <audio
                  v-else-if="(attachment.content_type || '').startsWith('audio/')"
                  :src="attachment.url"
                  controls
                  preload="metadata"
                  class="group-chat-media__audio"
                />
                <video
                  v-else-if="(attachment.content_type || '').startsWith('video/')"
                  :src="attachment.url"
                  controls
                  preload="metadata"
                  class="group-chat-media__video"
                />
                <a
                  v-else
                  :href="attachment.url"
                  target="_blank"
                  rel="noopener noreferrer"
                  class="group-chat-media__file"
                >
                  <fluent-icon icon="document" size="18" />
                  <span>{{ attachment.name }}</span>
                </a>
              </div>

              <span
                v-if="['image', 'audio', 'video', 'document', 'sticker'].includes(message.kind) && !message.files.length"
                class="group-chat-bubble__waiting"
              >
                {{ $t('GROUP_MANAGEMENT.WAITING_FILE') }}
              </span>
            </template>

            <div class="group-chat-bubble__meta">
              <time>{{ timestamp(message.sent_at) }}</time>
              <span v-if="message.direction === 'outgoing'" class="group-chat-bubble__status">
                {{ $t(`GROUP_MANAGEMENT.STATUS_${message.status.toUpperCase()}`) }}
              </span>
            </div>
          </div>

          <div class="group-chat-row__actions">
            <button
              v-if="canSend && message.source_id && !message.deleted_at"
              type="button"
              @click="reply = message"
            >
              {{ $t('GROUP_MANAGEMENT.REPLY') }}
            </button>
            <button
              v-if="!legacy && message.can_revoke"
              type="button"
              @click="revoke(message)"
            >
              {{ $t('GROUP_MANAGEMENT.REVOKE') }}
            </button>
            <button
              v-if="!legacy && message.can_cancel"
              type="button"
              @click="cancelPending(message)"
            >
              {{ $t('GROUP_MANAGEMENT.CANCEL_PENDING') }}
            </button>
          </div>
        </div>
      </article>
    </div>

    <form
      v-if="canSend"
      class="group-composer"
      @submit.prevent="send"
    >
      <div v-if="reply" class="group-composer__context">
        <span class="truncate">
          ↪ {{ $t('GROUP_MANAGEMENT.SELECTED_REPLY', { name: senderName(reply) }) }}
        </span>
        <button type="button" :disabled="sending" @click="reply = null">×</button>
      </div>
      <div v-if="file" class="group-composer__context">
        <span class="truncate">{{ file.name }}</span>
        <button type="button" :disabled="sending" @click="file = null">×</button>
      </div>

      <div class="group-composer__bar">
        <label class="group-composer__attach" :title="$t('GROUP_MANAGEMENT.ATTACH')">
          <fluent-icon icon="attach" size="20" />
          <input
            type="file"
            class="sr-only"
            :disabled="sending"
            :aria-label="$t('GROUP_MANAGEMENT.UPLOAD_FILE')"
            @change="chooseFile"
          />
        </label>

        <textarea
          v-model="text"
          maxlength="65536"
          rows="1"
          :disabled="sending"
          :placeholder="$t('GROUP_MANAGEMENT.MESSAGE')"
          :aria-label="$t('GROUP_MANAGEMENT.MESSAGE')"
          class="group-composer__input hub-scrollbar"
          @keydown.ctrl.enter.prevent="send"
        />

        <hub-button
          type="submit"
          icon="send"
          size="small"
          :disabled="sending || (!text.trim() && !file)"
          :title="$t('GROUP_MANAGEMENT.SEND')"
        />
      </div>
    </form>

    <GroupConfirm
      v-if="confirmRequest"
      :message="confirmRequest.message"
      @confirm="finishConfirmation(true)"
      @cancel="finishConfirmation(false)"
    />
  </section>
</template>
<style scoped>
.group-thread__header {
  display: flex;
  min-height: 58px;
  flex-shrink: 0;
  align-items: center;
  gap: 8px;
  padding: 8px 14px;
  border-bottom: 1px solid rgb(241 245 249);
}
.group-thread__title {
  margin: 0;
  overflow: hidden;
  color: rgb(15 23 42);
  font-size: 14px;
  font-weight: 600;
  text-overflow: ellipsis;
  white-space: nowrap;
}
.group-thread__subtitle {
  display: block;
  margin-top: 1px;
  color: rgb(148 163 184);
  font-size: 10px;
}
.group-thread__history {
  display: flex;
  min-height: 30px;
  align-items: center;
  gap: 14px;
  padding: 4px 16px;
  border-bottom: 1px solid rgb(248 250 252);
  color: rgb(100 116 139);
  font-size: 11px;
}
.group-thread__history button {
  border: 0;
  background: transparent;
  color: inherit;
}
.group-thread__history button.is-active { color: rgb(37 99 235); font-weight: 600; }
.group-thread__messages {
  min-height: 0;
  flex: 1;
  overflow-y: auto;
  padding: 18px 18px 22px;
  background:
    radial-gradient(circle at 24px 24px, rgb(148 163 184 / 0.035) 1px, transparent 1.2px) 0 0 / 24px 24px,
    rgb(248 250 252 / 0.45);
}
.group-chat-row {
  display: flex;
  max-width: 78%;
  align-items: flex-end;
  gap: 8px;
  margin: 7px 0;
}
.group-chat-row--outgoing {
  margin-left: auto;
  justify-content: flex-end;
}
.group-chat-row__avatar { flex: 0 0 30px; margin-bottom: 3px; }
.group-chat-row__body { min-width: 0; max-width: 100%; }
.group-chat-bubble {
  position: relative;
  min-width: 120px;
  overflow: hidden;
  border: 1px solid rgb(226 232 240);
  border-radius: 12px 12px 12px 4px;
  background: white;
  box-shadow: 0 1px 1px rgb(15 23 42 / 0.035);
  padding: 8px 10px 6px;
}
.group-chat-bubble--outgoing {
  border-color: rgb(219 234 254);
  border-radius: 12px 12px 4px 12px;
  background: rgb(239 246 255);
}
.group-chat-bubble__sender {
  margin-bottom: 3px;
  color: rgb(37 99 235);
  font-size: 11px;
  font-weight: 600;
}
.group-chat-bubble__text {
  margin: 0;
  color: rgb(30 41 59);
  font-size: 13px;
  line-height: 1.45;
  overflow-wrap: anywhere;
  white-space: pre-wrap;
}
.group-chat-bubble__deleted {
  margin: 0;
  color: rgb(148 163 184);
  font-size: 12px;
  font-style: italic;
}
.group-chat-bubble__reply-ref {
  display: block;
  width: 100%;
  margin: 0 0 6px;
  padding: 5px 7px;
  border: 0;
  border-left: 2px solid rgb(96 165 250);
  border-radius: 4px;
  background: rgb(248 250 252);
  color: rgb(100 116 139);
  font-size: 10px;
  text-align: left;
}
.group-chat-bubble__meta {
  display: flex;
  justify-content: flex-end;
  gap: 5px;
  margin-top: 4px;
  color: rgb(148 163 184);
  font-size: 9px;
  line-height: 12px;
}
.group-chat-bubble__status { color: rgb(59 130 246); }
.group-chat-bubble__waiting { color: rgb(148 163 184); font-size: 10px; }
.group-chat-media { margin-top: 6px; }
.group-chat-media__image-link { display: block; }
.group-chat-media__image {
  display: block;
  max-width: min(360px, 100%);
  max-height: 320px;
  border-radius: 8px;
  object-fit: contain;
}
.group-chat-media__audio { width: min(330px, 70vw); max-width: 100%; height: 36px; }
.group-chat-media__video { max-width: min(360px, 100%); max-height: 320px; border-radius: 8px; }
.group-chat-media__file {
  display: flex;
  max-width: 320px;
  align-items: center;
  gap: 7px;
  padding: 8px;
  border-radius: 7px;
  background: rgb(248 250 252);
  color: rgb(51 65 85);
  font-size: 11px;
}
.group-chat-row__actions {
  display: flex;
  gap: 10px;
  min-height: 18px;
  padding: 2px 4px 0;
  opacity: 0;
  transition: opacity 120ms ease;
}
.group-chat-row:hover .group-chat-row__actions,
.group-chat-row:focus-within .group-chat-row__actions { opacity: 1; }
.group-chat-row__actions button {
  border: 0;
  background: transparent;
  color: rgb(100 116 139);
  font-size: 10px;
}
.group-chat-row__actions button:hover { color: rgb(37 99 235); }
.group-composer {
  flex-shrink: 0;
  padding: 8px 12px 10px;
  border-top: 1px solid rgb(241 245 249);
  background: white;
}
.group-composer__context {
  display: flex;
  align-items: center;
  justify-content: space-between;
  gap: 8px;
  margin: 0 4px 6px;
  padding: 5px 8px;
  border-left: 2px solid rgb(59 130 246);
  border-radius: 4px;
  background: rgb(248 250 252);
  color: rgb(100 116 139);
  font-size: 10px;
}
.group-composer__context button { border: 0; background: transparent; color: inherit; font-size: 16px; }
.group-composer__bar {
  display: flex;
  min-height: 42px;
  align-items: flex-end;
  gap: 7px;
  padding: 5px 6px 5px 9px;
  border: 1px solid rgb(226 232 240);
  border-radius: 10px;
  background: white;
}
.group-composer__attach {
  display: inline-flex;
  width: 30px;
  height: 30px;
  align-items: center;
  justify-content: center;
  margin: 0;
  color: rgb(100 116 139);
  cursor: pointer;
}
.group-composer__input {
  min-height: 30px;
  max-height: 110px;
  flex: 1;
  resize: none;
  overflow-y: auto;
  margin: 0;
  padding: 5px 2px;
  border: 0;
  background: transparent;
  box-shadow: none;
  font-size: 13px;
  line-height: 20px;
}
.group-composer__input:focus { outline: none; box-shadow: none; }
.dark .group-thread__header { border-color: rgb(30 41 59); }
.dark .group-thread__title { color: rgb(226 232 240); }
.dark .group-thread__history { border-color: rgb(30 41 59); }
.dark .group-thread__messages { background-color: rgb(15 23 42 / 0.7); }
.dark .group-chat-bubble { border-color: rgb(51 65 85); background: rgb(30 41 59); }
.dark .group-chat-bubble--outgoing { border-color: rgb(30 64 175 / 0.5); background: rgb(30 58 138 / 0.34); }
.dark .group-chat-bubble__text { color: rgb(226 232 240); }
.dark .group-chat-bubble__reply-ref,
.dark .group-chat-media__file,
.dark .group-composer__context { background: rgb(15 23 42); }
.dark .group-composer { border-color: rgb(30 41 59); background: rgb(15 23 42); }
.dark .group-composer__bar { border-color: rgb(51 65 85); background: rgb(30 41 59); }

@media (max-width: 700px) {
  .group-chat-row { max-width: 92%; }
  .group-thread__messages { padding-inline: 10px; }
}
</style>
