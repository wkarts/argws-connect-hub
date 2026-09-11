<script>
import connectApiCalls from 'dashboard/api/connectApiCalls';
import { ConnectApiVoiceMediaSession } from 'dashboard/services/connectApiVoiceMedia';
import { BUS_EVENTS } from 'shared/constants/busEvents';

const ENDED_STATES = [
  'ended',
  'end',
  'terminated',
  'rejected',
  'closed',
  'failed',
  'missed',
  'unanswered',
  'answered_elsewhere',
  'cancelled',
  'canceled',
  'disconnected',
];
const CALL_POLL_INTERVAL = 3000;
const CALL_CLOCK_INTERVAL = 1000;
const REALTIME_REFRESH_DELAY = 50;

export default {
  props: {
    conversationId: {
      type: [String, Number],
      required: true,
    },
    inbox: {
      type: Object,
      required: true,
    },
    contact: {
      type: Object,
      default: () => ({}),
    },
  },
  data() {
    return {
      open: false,
      minimized: false,
      loading: false,
      busy: false,
      calls: [],
      capabilities: {},
      error: '',
      feedback: '',
      pollTimer: null,
      clockTimer: null,
      realtimeRefreshTimer: null,
      clockNow: Date.now(),
      callTimerStarts: {},
      voiceSession: null,
      mediaCallId: '',
      mediaState: 'idle',
      mediaError: '',
    };
  },
  computed: {
    providerConfig() {
      return this.inbox.provider_config || {};
    },
    callsSupported() {
      const value = this.providerConfig.calls_supported;
      return (
        value === true ||
        value === 1 ||
        String(value).toLowerCase() === 'true' ||
        String(value) === '1'
      );
    },
    visible() {
      return this.inbox.provider === 'connectapi' && this.callsSupported;
    },
    activeCalls() {
      return this.calls.filter(call => this.isActive(call));
    },
    primaryCall() {
      return (
        this.activeCalls.find(call => this.canAccept(call)) ||
        this.activeCalls[0] ||
        null
      );
    },
    hasActiveCall() {
      return Boolean(this.primaryCall);
    },
    hasIncomingCall() {
      return this.activeCalls.some(call => this.canAccept(call));
    },
    contactName() {
      return (
        this.contact?.name ||
        this.primaryCall?.name ||
        this.primaryCall?.contactName ||
        this.primaryCall?.pushName ||
        'Contato'
      );
    },
    contactThumbnail() {
      return this.contact?.thumbnail || '';
    },
    contactPhone() {
      return this.formatPhone(
        this.contact?.phone_number ||
          this.primaryCall?.number ||
          this.primaryCall?.phoneNumber ||
          this.primaryCall?.callerPn ||
          this.primaryCall?.displayPeerJid ||
          ''
      );
    },
    compactActionLabel() {
      return this.primaryCall && this.canReject(this.primaryCall)
        ? 'Recusar'
        : 'Encerrar';
    },
    currentDuration() {
      return this.primaryCall ? this.callDurationLabel(this.primaryCall) : '';
    },
    currentStateLabel() {
      return this.primaryCall ? this.stateLabel(this.primaryCall) : 'Pronto para ligar';
    },
    currentDirectionLabel() {
      return this.primaryCall ? this.directionLabel(this.primaryCall) : '';
    },
    mediaStateLabel() {
      const labels = {
        idle: 'Áudio não conectado',
        requesting_microphone: 'Aguardando permissão do microfone',
        connecting: 'Conectando áudio',
        ready: 'Áudio conectado',
        closed: 'Áudio encerrado',
        error: 'Falha no áudio',
      };
      return labels[this.mediaState] || this.mediaState;
    },
    mediaStateClass() {
      if (this.mediaState === 'ready') {
        return 'text-emerald-700 dark:text-emerald-300';
      }
      if (this.mediaState === 'error') {
        return 'text-red-700 dark:text-red-300';
      }
      return 'text-slate-500 dark:text-slate-400';
    },
    stateDotClass() {
      if (this.hasIncomingCall) return 'bg-amber-500 animate-pulse';
      if (this.primaryCall && this.isConnected(this.primaryCall)) return 'bg-emerald-500';
      if (this.hasActiveCall) return 'bg-blue-500 animate-pulse';
      return 'bg-slate-300 dark:bg-slate-600';
    },
    stateBadgeClass() {
      if (this.hasIncomingCall) {
        return 'bg-amber-50 text-amber-700 dark:bg-amber-950/30 dark:text-amber-300';
      }
      if (this.primaryCall && this.isConnected(this.primaryCall)) {
        return 'bg-emerald-50 text-emerald-700 dark:bg-emerald-950/30 dark:text-emerald-300';
      }
      if (this.hasActiveCall) {
        return 'bg-blue-50 text-blue-700 dark:bg-blue-950/30 dark:text-blue-300';
      }
      return 'bg-slate-100 text-slate-600 dark:bg-slate-800 dark:text-slate-300';
    },
  },
  watch: {
    conversationId() {
      this.resetConversationState();
      if (this.visible) this.loadCalls(true);
    },
    visible(isVisible) {
      if (isVisible) {
        this.loadCalls(true);
        this.startPolling();
        this.startClock();
        return;
      }

      this.stopPolling();
      this.stopClock();
      this.clearRealtimeRefresh();
      this.resetConversationState();
    },
  },
  mounted() {
    this.$emitter.on(
      BUS_EVENTS.CALL_TIMELINE_UPDATED,
      this.onCallTimelineUpdated
    );
    if (this.visible) {
      this.loadCalls(true);
      this.startPolling();
      this.startClock();
    }
  },
  beforeDestroy() {
    this.$emitter.off(
      BUS_EVENTS.CALL_TIMELINE_UPDATED,
      this.onCallTimelineUpdated
    );
    this.stopPolling();
    this.stopClock();
    this.clearRealtimeRefresh();
    this.closeMedia();
  },
  methods: {
    resetConversationState() {
      this.closeMedia();
      this.open = false;
      this.minimized = false;
      this.calls = [];
      this.callTimerStarts = {};
      this.error = '';
      this.feedback = '';
      this.mediaError = '';
    },
    async toggle() {
      if (this.open) {
        this.close();
        return;
      }
      await this.restore();
    },
    async restore() {
      this.minimized = false;
      this.open = true;
      await this.loadCalls();
    },
    minimize() {
      this.open = false;
      this.minimized = Boolean(this.primaryCall);
    },
    close() {
      if (this.primaryCall) {
        this.minimize();
        return;
      }
      this.open = false;
      this.minimized = false;
      this.feedback = '';
      this.error = '';
      this.mediaError = '';
    },
    startPolling() {
      this.stopPolling();
      this.pollTimer = window.setInterval(
        () => this.loadCalls(true),
        CALL_POLL_INTERVAL
      );
    },
    stopPolling() {
      if (this.pollTimer) window.clearInterval(this.pollTimer);
      this.pollTimer = null;
    },
    startClock() {
      this.stopClock();
      this.clockNow = Date.now();
      this.clockTimer = window.setInterval(() => {
        this.clockNow = Date.now();
      }, CALL_CLOCK_INTERVAL);
    },
    stopClock() {
      if (this.clockTimer) window.clearInterval(this.clockTimer);
      this.clockTimer = null;
    },
    clearRealtimeRefresh() {
      if (this.realtimeRefreshTimer) {
        window.clearTimeout(this.realtimeRefreshTimer);
      }
      this.realtimeRefreshTimer = null;
    },
    onCallTimelineUpdated({ conversationId } = {}) {
      if (!this.visible) return;
      if (String(conversationId) !== String(this.conversationId)) return;

      this.clearRealtimeRefresh();
      this.realtimeRefreshTimer = window.setTimeout(() => {
        this.realtimeRefreshTimer = null;
        this.loadCalls(true);
      }, REALTIME_REFRESH_DELAY);
    },
    isActive(call) {
      const state = String(call.state || call.status || '').toLowerCase();
      if (
        call.terminal === true ||
        String(call.terminal).toLowerCase() === 'true'
      ) {
        return false;
      }
      return !ENDED_STATES.some(
        terminalState =>
          state === terminalState ||
          state.startsWith(`${terminalState}_`) ||
          state.startsWith(`${terminalState}-`)
      );
    },
    isConnected(call) {
      if (!this.isActive(call)) return false;
      const state = String(call.state || call.status || '').toLowerCase();
      return (
        state.includes('accept') ||
        state.includes('active') ||
        state === 'answered' ||
        state === 'connected' ||
        state === 'connect'
      );
    },
    canAccept(call) {
      if (call.direction !== 'incoming' || !this.isActive(call)) return false;
      if (call.canAccept !== undefined && call.canAccept !== null) {
        return Boolean(call.canAccept);
      }
      const state = String(call.state || call.status || '').toLowerCase();
      return (
        state.includes('ring') ||
        state.includes('incoming') ||
        state.includes('offer')
      );
    },
    canReject(call) {
      if (call.direction !== 'incoming' || !this.isActive(call)) return false;
      if (call.canReject !== undefined && call.canReject !== null) {
        return Boolean(call.canReject);
      }
      return this.canAccept(call);
    },
    callId(call) {
      return String(call.callId || call.id || '');
    },
    timestampToMilliseconds(value) {
      if (value === undefined || value === null || value === '') return null;

      const numeric = Number(value);
      if (Number.isFinite(numeric)) {
        const milliseconds = numeric < 100000000000 ? numeric * 1000 : numeric;
        return milliseconds > 0 ? milliseconds : null;
      }

      const parsed = Date.parse(String(value));
      return Number.isNaN(parsed) ? null : parsed;
    },
    providerCallStart(call) {
      const candidates = [
        call.answeredAt,
        call.answered_at,
        call.acceptedAt,
        call.accepted_at,
        call.connectedAt,
        call.connected_at,
        call.startedAt,
        call.started_at,
        call.startTime,
        call.start_time,
      ];

      return candidates.reduce(
        (startedAt, candidate) =>
          startedAt || this.timestampToMilliseconds(candidate),
        null
      );
    },
    syncCallTimerStarts() {
      const nextStarts = {};

      this.activeCalls.forEach(call => {
        const id = this.callId(call);
        if (!id || !this.isConnected(call)) return;

        nextStarts[id] =
          this.providerCallStart(call) ||
          this.callTimerStarts[id] ||
          Date.now();
      });

      this.callTimerStarts = nextStarts;
    },
    callDurationLabel(call) {
      if (!call || !this.isConnected(call)) return '';
      const startedAt = this.callTimerStarts[this.callId(call)];
      if (!startedAt) return '00:00';

      const totalSeconds = Math.max(
        0,
        Math.floor((this.clockNow - startedAt) / 1000)
      );
      const hours = Math.floor(totalSeconds / 3600);
      const minutes = Math.floor((totalSeconds % 3600) / 60);
      const seconds = totalSeconds % 60;
      const minuteText = String(minutes).padStart(2, '0');
      const secondText = String(seconds).padStart(2, '0');

      if (hours > 0) {
        return `${hours}:${minuteText}:${secondText}`;
      }
      return `${minuteText}:${secondText}`;
    },
    async loadCalls(silent = false) {
      if (!silent) this.loading = true;
      if (!silent) this.error = '';
      try {
        const { data } = await connectApiCalls.status(this.conversationId);
        this.calls = Array.isArray(data.calls) ? data.calls : [];
        this.capabilities = data.capabilities || {};
        this.syncCallTimerStarts();

        if (this.activeCalls.length === 0) {
          this.minimized = false;
        } else if (!this.open) {
          this.minimized = true;
        }

        if (this.mediaCallId) {
          const current = this.calls.find(
            call => this.callId(call) === this.mediaCallId
          );
          if (!current || !this.isActive(current)) this.closeMedia();
        }
      } catch (error) {
        if (!silent) this.error = this.apiError(error);
      } finally {
        if (!silent) this.loading = false;
      }
    },
    async makeCall() {
      this.busy = true;
      this.error = '';
      this.feedback = '';
      try {
        const { data } = await connectApiCalls.offer(this.conversationId);
        const callId = String(data.callId || data.id || '');
        this.feedback = 'Chamando…';
        if (callId && this.capabilities.voice !== false) {
          await this.attachMedia(callId);
        }
        await this.loadCalls(true);
      } catch (error) {
        this.error = this.apiError(error);
      } finally {
        this.busy = false;
      }
    },
    async compactAccept() {
      if (!this.primaryCall || !this.canAccept(this.primaryCall)) return;
      await this.action(this.primaryCall, 'accept');
    },
    async compactEnd() {
      if (!this.primaryCall) return;
      const action = this.canReject(this.primaryCall) ? 'reject' : 'end_call';
      await this.action(this.primaryCall, action);
    },
    async action(call, action) {
      const callId = this.callId(call);
      if (!callId) return;
      this.busy = true;
      this.error = '';
      this.feedback = '';
      try {
        const nextMuted = !Boolean(call.muted);
        const payload =
          action === 'mute'
            ? { call_id: callId, muted: nextMuted }
            : { call_id: callId };
        await connectApiCalls.action(this.conversationId, action, payload);
        if (action === 'accept') {
          await this.attachMedia(callId);
          this.feedback = 'Chamada atendida.';
        } else if (action === 'reject') {
          if (this.mediaCallId === callId) this.closeMedia();
          this.feedback = 'Chamada recusada.';
        } else if (action === 'end_call') {
          if (this.mediaCallId === callId) this.closeMedia();
          this.feedback = 'Chamada encerrada.';
        } else if (action === 'mute') {
          if (this.mediaCallId === callId && this.voiceSession) {
            this.voiceSession.setMicMuted(nextMuted);
          }
          this.feedback = nextMuted
            ? 'Microfone silenciado.'
            : 'Microfone ativado.';
        }
        await this.loadCalls(true);
      } catch (error) {
        this.error = this.apiError(error);
      } finally {
        this.busy = false;
      }
    },
    async requestMediaTicket(callId) {
      let lastError = null;
      for (let attempt = 0; attempt < 3; attempt += 1) {
        try {
          return await connectApiCalls.mediaTicket(
            this.conversationId,
            callId
          );
        } catch (error) {
          lastError = error;
          if (error?.response?.status !== 404 || attempt === 2) throw error;
          await new Promise(resolve =>
            window.setTimeout(resolve, 250 * (attempt + 1))
          );
        }
      }
      throw lastError;
    },
    async attachMedia(callId) {
      this.closeMedia();
      this.mediaCallId = callId;
      this.mediaError = '';
      try {
        const { data } = await this.requestMediaTicket(callId);
        this.voiceSession = new ConnectApiVoiceMediaSession(
          { mediaUrl: data.media_url, ticket: data.ticket },
          {
            onState: state => {
              this.mediaState = state;
            },
            onError: message => {
              this.mediaError = message;
            },
          }
        );
        await this.voiceSession.start();
      } catch (error) {
        this.mediaError = this.apiError(error);
        this.mediaState = 'error';
        if (this.voiceSession) this.voiceSession.stop();
        this.voiceSession = null;
      }
    },
    closeMedia() {
      if (this.voiceSession) this.voiceSession.stop();
      this.voiceSession = null;
      this.mediaCallId = '';
      if (this.mediaState !== 'error') this.mediaState = 'idle';
    },
    directionLabel(call) {
      if (call.direction === 'incoming') return 'Recebida';
      if (call.direction === 'outgoing') return 'Efetuada';
      return 'Chamada';
    },
    stateLabel(call) {
      if (this.canAccept(call)) return 'Recebendo chamada';

      const state = String(call.state || call.status || '').toLowerCase();
      if (state.includes('ring')) return 'Chamando';
      if (
        state.includes('accept') ||
        state.includes('active') ||
        state === 'answered' ||
        state === 'connected' ||
        state === 'connect'
      ) {
        return 'Em andamento';
      }
      if (state.includes('reject')) return 'Recusada';
      if (state.includes('miss')) return 'Perdida';
      if (state.includes('unanswered')) return 'Não atendida';
      if (state.includes('fail')) return 'Falhou';
      if (
        state.includes('end') ||
        state.includes('termin') ||
        state.includes('close') ||
        state.includes('disconnect')
      ) {
        return 'Encerrada';
      }
      return call.state || call.status || 'Em andamento';
    },
    peerLabel(call) {
      return (
        this.contactName ||
        call.name ||
        call.contactName ||
        call.number ||
        call.phoneNumber ||
        call.callerPn ||
        call.displayPeerJid ||
        call.peerJid ||
        'WhatsApp'
      );
    },
    formatPhone(value) {
      const digits = String(value || '').replace(/\D/g, '');
      if (!digits) return '';

      if (digits.startsWith('55') && digits.length === 13) {
        return `+55 (${digits.slice(2, 4)}) ${digits.slice(4, 9)}-${digits.slice(9)}`;
      }
      if (digits.startsWith('55') && digits.length === 12) {
        return `+55 (${digits.slice(2, 4)}) ${digits.slice(4, 8)}-${digits.slice(8)}`;
      }
      return `+${digits}`;
    },
    apiError(error) {
      return (
        error?.response?.data?.error ||
        error?.response?.data?.message ||
        error?.message ||
        'Falha ao comunicar com o serviço de chamadas.'
      );
    },
  },
};
</script>

<template>
  <div v-if="visible" class="relative flex min-w-0 items-center gap-2">
    <div
      v-if="minimized && primaryCall"
      class="flex min-w-0 items-center gap-2 rounded-xl border border-slate-200 bg-white px-2 py-1.5 shadow-sm dark:border-slate-700 dark:bg-slate-900"
    >
      <button
        type="button"
        class="flex min-w-0 items-center gap-2 rounded-lg px-1 py-0.5 text-left hover:bg-slate-50 focus:outline-none focus:ring-2 focus:ring-blue-500 dark:hover:bg-slate-800"
        title="Reexibir chamada"
        @click="restore"
      >
        <div class="relative shrink-0">
          <hub-thumbnail
            :src="contactThumbnail"
            :username="contactName"
            size="34px"
          />
          <span
            class="absolute -bottom-0.5 -right-0.5 h-2.5 w-2.5 rounded-full ring-2 ring-white dark:ring-slate-900"
            :class="stateDotClass"
          />
        </div>
        <span class="min-w-0">
          <span class="block max-w-[150px] truncate text-xs font-semibold text-slate-900 dark:text-slate-100">
            {{ contactName }}
          </span>
          <span class="block max-w-[170px] truncate text-[11px] text-slate-500 dark:text-slate-400">
            {{ currentStateLabel }}
            <template v-if="currentDuration"> · {{ currentDuration }}</template>
          </span>
        </span>
      </button>

      <button
        v-if="canAccept(primaryCall)"
        type="button"
        class="rounded-lg bg-emerald-600 px-2.5 py-1.5 text-xs font-semibold text-white hover:bg-emerald-700 disabled:cursor-not-allowed disabled:opacity-50"
        :disabled="busy"
        @click="compactAccept"
      >
        Atender
      </button>
      <button
        type="button"
        class="rounded-lg border border-slate-200 bg-white px-2.5 py-1.5 text-xs font-medium text-slate-700 hover:bg-slate-50 disabled:cursor-not-allowed disabled:opacity-50 dark:border-slate-700 dark:bg-slate-900 dark:text-slate-200 dark:hover:bg-slate-800"
        :disabled="busy"
        @click="restore"
      >
        Exibir
      </button>
      <button
        type="button"
        class="rounded-lg bg-red-600 px-2.5 py-1.5 text-xs font-semibold text-white hover:bg-red-700 disabled:cursor-not-allowed disabled:opacity-50"
        :disabled="busy"
        @click="compactEnd"
      >
        {{ compactActionLabel }}
      </button>
    </div>

    <div v-if="!minimized" class="relative shrink-0">
      <hub-button
        v-tooltip="hasIncomingCall ? 'Chamada recebida' : 'Chamada WhatsApp'"
        variant="clear"
        color-scheme="secondary"
        icon="call"
        @click="toggle"
      />
      <span
        v-if="hasIncomingCall"
        class="pointer-events-none absolute right-1 top-1 h-2.5 w-2.5 rounded-full bg-amber-500 ring-2 ring-white dark:ring-slate-900"
      />
    </div>

    <div
      v-if="open"
      class="fixed inset-0 z-50 flex items-center justify-center bg-slate-950/40 p-4 backdrop-blur-[1px]"
      @click.self="close"
    >
      <div
        class="w-full max-w-[430px] overflow-hidden rounded-2xl border border-slate-200 bg-white shadow-2xl dark:border-slate-700 dark:bg-slate-900"
      >
        <div class="flex items-center justify-between gap-3 border-b border-slate-100 px-4 py-3.5 dark:border-slate-800">
          <div class="flex min-w-0 items-center gap-3">
            <div class="relative shrink-0">
              <hub-thumbnail
                :src="contactThumbnail"
                :username="contactName"
                size="44px"
              />
              <span
                class="absolute -bottom-0.5 -right-0.5 h-3 w-3 rounded-full ring-2 ring-white dark:ring-slate-900"
                :class="stateDotClass"
              />
            </div>
            <div class="min-w-0">
              <h3 class="m-0 truncate text-sm font-semibold text-slate-900 dark:text-slate-100">
                {{ contactName }}
              </h3>
              <p class="m-0 mt-0.5 truncate text-xs text-slate-500 dark:text-slate-400">
                {{ contactPhone || 'Número indisponível' }}
              </p>
            </div>
          </div>

          <button
            v-if="hasActiveCall"
            type="button"
            class="flex h-8 w-8 items-center justify-center rounded-lg text-lg font-semibold text-slate-500 hover:bg-slate-100 hover:text-slate-800 focus:outline-none focus:ring-2 focus:ring-blue-500 dark:text-slate-400 dark:hover:bg-slate-800 dark:hover:text-slate-100"
            title="Minimizar chamada"
            aria-label="Minimizar chamada"
            @click="minimize"
          >
            —
          </button>
          <button
            v-else
            type="button"
            class="flex h-8 w-8 items-center justify-center rounded-lg text-xl text-slate-400 hover:bg-slate-100 hover:text-slate-700 focus:outline-none focus:ring-2 focus:ring-blue-500 dark:hover:bg-slate-800 dark:hover:text-slate-200"
            title="Fechar"
            aria-label="Fechar"
            @click="close"
          >
            ×
          </button>
        </div>

        <div class="px-4 py-4">
          <div
            v-if="error"
            class="mb-3 rounded-xl bg-red-50 px-3 py-2 text-sm text-red-700 dark:bg-red-950/30 dark:text-red-300"
          >
            {{ error }}
          </div>
          <div
            v-if="mediaError"
            class="mb-3 rounded-xl bg-amber-50 px-3 py-2 text-sm text-amber-700 dark:bg-amber-950/30 dark:text-amber-300"
          >
            {{ mediaError }}
          </div>
          <div
            v-if="feedback"
            class="mb-3 rounded-xl bg-emerald-50 px-3 py-2 text-sm text-emerald-700 dark:bg-emerald-950/30 dark:text-emerald-300"
          >
            {{ feedback }}
          </div>

          <div v-if="loading" class="py-8 text-center text-sm text-slate-500">
            Carregando chamada…
          </div>

          <template v-else-if="primaryCall">
            <div class="rounded-2xl bg-slate-50 px-4 py-4 dark:bg-slate-800/60">
              <div class="flex items-center justify-between gap-3">
                <div class="min-w-0">
                  <span
                    class="inline-flex rounded-full px-2.5 py-1 text-[11px] font-semibold"
                    :class="stateBadgeClass"
                  >
                    {{ currentDirectionLabel }} · {{ currentStateLabel }}
                  </span>
                  <div
                    v-if="currentDuration"
                    class="mt-2 font-mono text-2xl font-semibold tabular-nums text-slate-900 dark:text-slate-100"
                  >
                    {{ currentDuration }}
                  </div>
                  <div
                    v-else
                    class="mt-2 text-sm font-medium text-slate-800 dark:text-slate-100"
                  >
                    {{ currentStateLabel }}
                  </div>
                </div>

                <div class="flex h-12 w-12 shrink-0 items-center justify-center rounded-full bg-white text-xl shadow-sm ring-1 ring-slate-200 dark:bg-slate-900 dark:ring-slate-700">
                  ☎
                </div>
              </div>

              <div class="mt-4 flex flex-wrap items-center gap-2">
                <button
                  v-if="canAccept(primaryCall)"
                  type="button"
                  class="flex-1 rounded-xl bg-emerald-600 px-4 py-2.5 text-sm font-semibold text-white hover:bg-emerald-700 disabled:cursor-not-allowed disabled:opacity-50"
                  :disabled="busy"
                  @click="action(primaryCall, 'accept')"
                >
                  Atender
                </button>
                <button
                  v-if="canReject(primaryCall)"
                  type="button"
                  class="flex-1 rounded-xl bg-red-600 px-4 py-2.5 text-sm font-semibold text-white hover:bg-red-700 disabled:cursor-not-allowed disabled:opacity-50"
                  :disabled="busy"
                  @click="action(primaryCall, 'reject')"
                >
                  Recusar
                </button>
                <button
                  v-if="mediaCallId === callId(primaryCall)"
                  type="button"
                  class="flex-1 rounded-xl border border-slate-200 bg-white px-4 py-2.5 text-sm font-medium text-slate-700 hover:bg-slate-100 disabled:cursor-not-allowed disabled:opacity-50 dark:border-slate-700 dark:bg-slate-900 dark:text-slate-200 dark:hover:bg-slate-800"
                  :disabled="busy"
                  @click="action(primaryCall, 'mute')"
                >
                  {{ primaryCall.muted ? 'Ativar microfone' : 'Silenciar' }}
                </button>
                <button
                  v-if="!canReject(primaryCall)"
                  type="button"
                  class="flex-1 rounded-xl bg-red-600 px-4 py-2.5 text-sm font-semibold text-white hover:bg-red-700 disabled:cursor-not-allowed disabled:opacity-50"
                  :disabled="busy"
                  @click="action(primaryCall, 'end_call')"
                >
                  Encerrar
                </button>
              </div>
            </div>

            <div class="mt-3 flex items-center justify-between gap-3 rounded-xl border border-slate-200 px-3 py-2.5 dark:border-slate-700">
              <div class="flex min-w-0 items-center gap-2">
                <span class="flex h-7 w-7 shrink-0 items-center justify-center rounded-lg bg-slate-100 text-sm dark:bg-slate-800">
                  ♪
                </span>
                <div class="min-w-0">
                  <div class="text-xs font-semibold text-slate-800 dark:text-slate-100">
                    Áudio da chamada
                  </div>
                  <div class="truncate text-[11px]" :class="mediaStateClass">
                    {{ mediaStateLabel }}
                  </div>
                </div>
              </div>
              <button
                type="button"
                class="rounded-lg px-2 py-1 text-xs font-medium text-slate-500 hover:bg-slate-100 hover:text-slate-800 dark:hover:bg-slate-800 dark:hover:text-slate-200"
                :disabled="busy"
                @click="loadCalls()"
              >
                Atualizar
              </button>
            </div>
          </template>

          <template v-else>
            <div class="rounded-2xl border border-slate-200 px-4 py-4 dark:border-slate-700">
              <div class="flex items-center gap-3">
                <hub-thumbnail
                  :src="contactThumbnail"
                  :username="contactName"
                  size="48px"
                />
                <div class="min-w-0 flex-1">
                  <div class="truncate text-sm font-semibold text-slate-900 dark:text-slate-100">
                    Pronto para ligar
                  </div>
                  <div class="mt-0.5 truncate text-xs text-slate-500 dark:text-slate-400">
                    Inicie uma chamada de voz com {{ contactName }}.
                  </div>
                </div>
              </div>

              <button
                type="button"
                class="mt-4 flex w-full items-center justify-center gap-2 rounded-xl bg-blue-600 px-4 py-2.5 text-sm font-semibold text-white hover:bg-blue-700 disabled:cursor-not-allowed disabled:opacity-50"
                :disabled="busy || loading"
                @click="makeCall"
              >
                <span aria-hidden="true">☎</span>
                Ligar para este contato
              </button>
            </div>
          </template>
        </div>
      </div>
    </div>
  </div>
</template>
