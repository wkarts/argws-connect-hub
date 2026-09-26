<script>
import api from 'dashboard/api/whatsappGroups';
import {
  GROUP_EVENT,
  groupFailure,
  groupDestination,
} from 'dashboard/helper/whatsappGroups.mjs';
import { BUS_EVENTS } from 'shared/constants/busEvents';

export default {
  props: {
    inboxId: { type: [Number, String], default: 0 },
    active: Boolean,
  },
  data() {
    return {
      rows: [],
      total: 0,
      page: 1,
      perPage: 50,
      query: '',
      loading: false,
      loadingMore: false,
      error: '',
      sequence: 0,
      timer: null,
    };
  },
  computed: {
    accountId() {
      return this.$store.getters.getCurrentAccountId;
    },
    scope() {
      return `${this.accountId}:${this.inboxId}`;
    },
    hasMore() {
      return this.rows.length < this.total;
    },
  },
  watch: {
    scope: {
      immediate: true,
      handler() {
        this.sequence += 1;
        this.rows = [];
        this.total = 0;
        this.page = 1;
        this.load(1);
      },
    },
    active(value) {
      if (value) this.scheduleRefresh();
    },
  },
  mounted() {
    this.$emitter.on(GROUP_EVENT, this.changed);
    this.$emitter.on(BUS_EVENTS.WEBSOCKET_RECONNECT, this.scheduleRefresh);
    window.addEventListener('focus', this.scheduleRefresh);
    window.addEventListener('online', this.scheduleRefresh);
  },
  beforeDestroy() {
    this.sequence += 1;
    clearTimeout(this.timer);
    this.$emitter.off(GROUP_EVENT, this.changed);
    this.$emitter.off(BUS_EVENTS.WEBSOCKET_RECONNECT, this.scheduleRefresh);
    window.removeEventListener('focus', this.scheduleRefresh);
    window.removeEventListener('online', this.scheduleRefresh);
  },
  methods: {
    changed(event) {
      if (
        Number(event.account_id) !== Number(this.accountId) ||
        (this.inboxId && Number(event.inbox_id) !== Number(this.inboxId))
      ) {
        return;
      }

      if (event.invalidated) {
        this.rows = this.rows.filter(group =>
          event.group_id
            ? Number(group.id) !== Number(event.group_id)
            : Number(group.inbox_id) !== Number(event.inbox_id)
        );
        this.total = Math.max(0, this.total - 1);
      }
      this.scheduleRefresh();
    },
    scheduleRefresh() {
      clearTimeout(this.timer);
      this.timer = setTimeout(() => this.load(1), 160);
    },
    async load(page = 1, append = false) {
      if (append && (this.loadingMore || !this.hasMore)) return;
      const sequence = ++this.sequence;
      const scope = this.scope;
      if (append) this.loadingMore = true;
      else this.loading = true;
      this.error = '';

      try {
        const { data } = await api.list(this.accountId, {
          ...(this.inboxId ? { inbox_id: this.inboxId } : {}),
          page,
          per_page: this.perPage,
          q: this.query,
        });
        if (sequence !== this.sequence || scope !== this.scope) return;

        const incoming = Array(data.groups || []);
        if (append) {
          const byId = new Map(this.rows.map(group => [Number(group.id), group]));
          incoming.forEach(group => byId.set(Number(group.id), group));
          this.rows = this.sortRows([...byId.values()]);
        } else {
          this.rows = this.sortRows(incoming);
        }
        this.total = Number(data.total || 0);
        this.page = Number(data.page || page);
        this.$emit('count', this.total);
      } catch (error) {
        if (sequence === this.sequence) {
          this.error = groupFailure(error, this.$t('GROUP_MANAGEMENT.ERROR'));
          if ([401, 403, 404].includes(error?.response?.status)) this.rows = [];
        }
      } finally {
        if (sequence === this.sequence) {
          this.loading = false;
          this.loadingMore = false;
        }
      }
    },
    async search() {
      this.page = 1;
      await this.load(1);
      this.$nextTick(() => {
        if (this.$refs.scroll) this.$refs.scroll.scrollTop = 0;
      });
    },
    onScroll(event) {
      const target = event.currentTarget;
      if (!target || !this.hasMore) return;
      if (target.scrollHeight - target.scrollTop - target.clientHeight < 120) {
        this.load(this.page + 1, true);
      }
    },
    sortRows(rows) {
      return [...rows].sort((left, right) => {
        if (Boolean(left.pinned) !== Boolean(right.pinned)) {
          return left.pinned ? -1 : 1;
        }
        if (left.pinned && right.pinned) {
          const pinOrder =
            new Date(right.pinned_at || 0).getTime() -
            new Date(left.pinned_at || 0).getTime();
          if (pinOrder) return pinOrder;
        }
        return (
          new Date(right.last_activity_at || 0).getTime() -
            new Date(left.last_activity_at || 0).getTime() ||
          Number(right.id) - Number(left.id)
        );
      });
    },
    open(group, history = false) {
      this.$router
        .push(groupDestination(this.accountId, group, history))
        .catch(() => {});
    },
    async toggleMute(group) {
      const scope = this.scope;
      try {
        const { data } = await api.preference(this.accountId, group.id, {
          muted: !group.muted,
        });
        if (scope === this.scope) this.$set(group, 'muted', data.muted);
      } catch (error) {
        if (scope === this.scope) {
          this.error = groupFailure(error, this.$t('GROUP_MANAGEMENT.ERROR'));
        }
      }
    },
    async togglePin(group) {
      const scope = this.scope;
      try {
        const { data } = await api.preference(this.accountId, group.id, {
          pinned: !group.pinned,
        });
        if (scope !== this.scope) return;
        this.$set(group, 'pinned', data.pinned);
        this.$set(group, 'pinned_at', data.pinned_at);
        this.rows = this.sortRows(this.rows);
      } catch (error) {
        if (scope === this.scope) {
          this.error = groupFailure(error, this.$t('GROUP_MANAGEMENT.ERROR'));
        }
      }
    },
    activityTime(value) {
      const date = new Date(value);
      if (Number.isNaN(date.getTime())) return '';
      const now = new Date();
      if (date.toDateString() === now.toDateString()) {
        return date.toLocaleTimeString([], { hour: '2-digit', minute: '2-digit' });
      }
      return date.toLocaleDateString([], { day: '2-digit', month: '2-digit' });
    },
    preview(group) {
      const body =
        group.last_message_preview ||
        (group.last_message_kind
          ? this.$t(
              `GROUP_MANAGEMENT.KIND_${String(group.last_message_kind).toUpperCase()}`,
              group.last_message_kind
            )
          : '');
      if (!body) return '';
      const sender = group.last_sender_name;
      return sender ? `${sender}: ${body}` : body;
    },
  },
};
</script>

<template>
  <section
    class="flex min-h-0 flex-1 flex-col"
    :aria-label="$t('GROUP_MANAGEMENT.TITLE')"
  >
    <form class="group-search" @submit.prevent="search">
      <fluent-icon icon="search" size="16" class="group-search__icon" />
      <input
        v-model.trim="query"
        maxlength="120"
        class="group-search__input"
        :placeholder="$t('GROUP_MANAGEMENT.SEARCH')"
        :aria-label="$t('GROUP_MANAGEMENT.SEARCH')"
      />
      <button
        v-if="query"
        type="button"
        class="group-search__clear"
        aria-label="Limpar busca"
        @click="query = ''; search()"
      >
        ×
      </button>
    </form>

    <p v-if="error" role="alert" class="px-3 py-1 text-xs text-red-600">
      {{ error }}
    </p>
    <p v-if="loading && !rows.length" role="status" class="px-3 py-2 text-xs text-slate-500">
      {{ $t('GROUP_MANAGEMENT.LOADING') }}
    </p>
    <p v-if="!loading && !rows.length" class="px-3 py-3 text-sm text-slate-500">
      {{ $t('GROUP_MANAGEMENT.EMPTY') }}
    </p>

    <div
      ref="scroll"
      class="group-list-scroll hub-scrollbar min-h-0 flex-1 overflow-y-auto"
      tabindex="0"
      @scroll.passive="onScroll"
    >
      <article
        v-for="group in rows"
        :key="group.id"
        class="group-row"
        :class="{ 'group-row--pinned': group.pinned }"
        :title="$t(group.treatment === 'management' ? 'GROUP_MANAGEMENT.MODE_MANAGEMENT' : 'GROUP_MANAGEMENT.MODE_CONVERSATION')"
      >
        <button type="button" class="group-row__main" @click="open(group)">
          <div class="group-row__avatar">
            <hub-thumbnail
              :src="group.avatar_url"
              :username="group.name"
              size="40px"
            />
            <span v-if="group.pinned" class="group-row__pin-mark" aria-hidden="true">•</span>
          </div>

          <span class="group-row__content">
            <span class="group-row__headline">
              <strong class="group-row__name">{{ group.name }}</strong>
              <time class="group-row__time">{{ activityTime(group.last_activity_at) }}</time>
            </span>
            <span class="group-row__footer">
              <span class="group-row__preview">{{ preview(group) }}</span>
              <span
                v-if="group.unread_count"
                class="group-row__unread"
                :aria-label="`${group.unread_count} não lidas`"
              >
                {{ group.unread_count > 99 ? '99+' : group.unread_count }}
              </span>
            </span>
          </span>
        </button>

        <div class="group-row__actions">
          <button
            type="button"
            class="group-row__action"
            :class="{ 'is-active': group.pinned }"
            :title="group.pinned ? 'Desafixar grupo' : 'Fixar grupo'"
            @click.stop="togglePin(group)"
          >
            <fluent-icon icon="pin" size="16" />
          </button>
          <button
            type="button"
            class="group-row__action"
            :class="{ 'is-active': group.muted }"
            :title="$t(group.muted ? 'GROUP_MANAGEMENT.UNMUTE' : 'GROUP_MANAGEMENT.MUTE')"
            @click.stop="toggleMute(group)"
          >
            <fluent-icon :icon="group.muted ? 'speaker-mute' : 'speaker-1'" size="16" />
          </button>
        </div>
      </article>

      <div v-if="loadingMore" class="py-3 text-center text-xs text-slate-400">
        {{ $t('GROUP_MANAGEMENT.LOADING') }}
      </div>
    </div>
  </section>
</template>

<style scoped>
.group-search {
  display: flex;
  align-items: center;
  gap: 0.45rem;
  min-height: 42px;
  margin: 8px 10px;
  padding: 0 10px;
  border-radius: 8px;
  background: rgb(248 250 252);
  color: rgb(100 116 139);
}
.group-search__icon { flex: 0 0 auto; }
.group-search__input {
  width: 100%;
  min-width: 0;
  margin: 0;
  padding: 0;
  border: 0;
  box-shadow: none;
  background: transparent;
  font-size: 13px;
}
.group-search__input:focus { box-shadow: none; outline: none; }
.group-search__clear {
  border: 0;
  background: transparent;
  color: inherit;
  font-size: 18px;
  line-height: 1;
}
.group-row {
  position: relative;
  min-height: 64px;
  border-bottom: 1px solid rgb(241 245 249);
}
.group-row:hover { background: rgb(248 250 252); }
.group-row__main {
  display: flex;
  width: 100%;
  min-width: 0;
  align-items: center;
  gap: 10px;
  padding: 10px 52px 10px 12px;
  border: 0;
  background: transparent;
  text-align: left;
}
.group-row__avatar { position: relative; flex: 0 0 40px; width: 40px; height: 40px; }
.group-row__pin-mark {
  position: absolute;
  right: -1px;
  bottom: 0;
  width: 9px;
  height: 9px;
  border: 2px solid white;
  border-radius: 999px;
  background: rgb(37 99 235);
  font-size: 0;
}
.group-row__content { min-width: 0; flex: 1; }
.group-row__headline,
.group-row__footer {
  display: flex;
  min-width: 0;
  align-items: center;
  gap: 8px;
}
.group-row__name {
  min-width: 0;
  flex: 1;
  overflow: hidden;
  color: rgb(30 41 59);
  font-size: 13px;
  font-weight: 600;
  text-overflow: ellipsis;
  white-space: nowrap;
}
.group-row__time { flex: 0 0 auto; color: rgb(148 163 184); font-size: 10px; }
.group-row__footer { margin-top: 3px; }
.group-row__preview {
  min-width: 0;
  flex: 1;
  overflow: hidden;
  color: rgb(100 116 139);
  font-size: 11px;
  line-height: 16px;
  text-overflow: ellipsis;
  white-space: nowrap;
}
.group-row__unread {
  flex: 0 0 auto;
  min-width: 19px;
  padding: 1px 5px;
  border-radius: 999px;
  background: rgb(37 99 235);
  color: white;
  font-size: 9px;
  font-weight: 600;
  text-align: center;
}
.group-row__actions {
  position: absolute;
  right: 7px;
  top: 50%;
  display: flex;
  align-items: center;
  opacity: 0;
  transform: translateY(-50%);
  transition: opacity 120ms ease;
}
.group-row:hover .group-row__actions,
.group-row:focus-within .group-row__actions { opacity: 1; }
.group-row__action {
  display: inline-flex;
  width: 22px;
  height: 28px;
  align-items: center;
  justify-content: center;
  border: 0;
  background: transparent;
  color: rgb(148 163 184);
}
.group-row__action:hover,
.group-row__action.is-active { color: rgb(37 99 235); }
.dark .group-search { background: rgb(30 41 59); color: rgb(148 163 184); }
.dark .group-row { border-color: rgb(30 41 59); }
.dark .group-row:hover { background: rgb(15 23 42 / 0.55); }
.dark .group-row__name { color: rgb(226 232 240); }
.dark .group-row__pin-mark { border-color: rgb(15 23 42); }
</style>
