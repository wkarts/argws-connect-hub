<script>
import connectApiCalls from 'dashboard/api/connectApiCalls';
import { ConnectApiVoiceMediaSession } from 'dashboard/services/connectApiVoiceMedia';

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
    visible() {
      return (
        this.inbox.provider === 'connectapi' &&
        (this.providerConfig.calls_supported ||
          this.providerConfig.connect_api_provider === 'WHATSAPP-ZAPO')
      );
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
    hasIncomingCall() {
      return this.activeCalls.some(call => this.canAccept(call));
    },
    compactActionLabel() {
      return this.primaryCall && this.canReject(this.primaryCall)
        ? 'Recusar'
        : 'Encerrar';
    },
    mediaStateLabel() {
      const labels = {
        idle: 'Áudio não conectado',
        requesting_microphone: 'Aguardando microfone',
        connecting: 'Conectando áudio',
        ready: 'Áudio conectado',
        closed: 'Áudio encerrado',
        error: 'Falha no áudio',
      };
      return labels[this.mediaState] || this.mediaState;
    },
  },
  watch: {
    conversationId() {
      this.closeMedia();
      this.open = false;
      this.minimized = false;
      this.calls = [];
      this.callTimerStarts = {};
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
      this.closeMedia();
      this.open = false;
      this.minimized = false;
      this.calls = [];
      this.callTimerStarts = {};
    },
  },
  mounted() {
    if (this.visible) {
      this.loadCalls(true);
      this.startPolling();
      this.startClock();
    }
  },
  beforeDestroy() {
    this.stopPolling();
    this.stopClock();
    this.closeMedia();
  },
  methods: {
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
    isActive(call) {
      const state = String(call.state || call.status || '').toLowerCase();
      if (call.terminal === true) return false;
      return !ENDED_STATES.includes(state);
    },
    isConnected(call) {
      if (!this.isActive(call)) return false;
      const state = String(call.state || call.status || '').toLowerCase();
      return (
        state.includes('accept') ||
        state.includes('active') ||
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

      for (const candidate of candidates) {
        const parsed = this.timestampToMilliseconds(candidate);
        if (parsed) return parsed;
      }
      return null;
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
        this.feedback = 'Chamada iniciada.';
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
          this.feedback = 'Chamada atendida; áudio conectado.';
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
        state === 'connected' ||
        state === 'connect'
      ) {
        return 'Em andamento';
      }
      if (state.includes('reject')) return 'Recusada';
      if (state.includes('miss')) return 'Perdida';
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
    apiError(error) {
      return (
        error?.response?.data?.error ||
        error?.response?.data?.message ||
        error?.message ||
        'Falha ao comunicar com a Connect|API.'
      );
    },
  },
};
</script>

<template>
  <div v-if="visible" class="relative flex min-w-0 items-center gap-2">
    <div
      v-if="minimized && primaryCall"
      class="flex min-w-0 items-center gap-2 rounded-xl border border-emerald-200 bg-emerald-50 px-2 py-1.5 shadow-sm dark:border-emerald-800 dark:bg-emerald-950/40"
    >
      <button
        type="button"
        class="flex min-w-0 items-center gap-2 rounded-lg px-1 py-0.5 text-left hover:bg-emerald-100 focus:outline-none focus:ring-2 focus:ring-emerald-500 dark:hover:bg-emerald-900/60"
        title="Reexibir chamada"
        @click="restore"
      >
        <span
          class="relative flex h-8 w-8 shrink-0 items-center justify-center rounded-full bg-emerald-600 text-base text-white shadow-sm"
          aria-hidden="true"
        >
          ☎
          <span
            class="absolute -right-0.5 -top-0.5 h-2.5 w-2.5 animate-pulse rounded-full bg-red-500 ring-2 ring-emerald-50 dark:ring-emerald-950"
          />
        </span>
        <span class="min-w-0">
          <span class="block truncate text-xs font-semibold text-emerald-950 dark:text-emerald-100">
            {{ stateLabel(primaryCall) }}
            <template v-if="callDurationLabel(primaryCall)">
              · {{ callDurationLabel(primaryCall) }}
            </template>
          </span>
          <span class="block max-w-[150px] truncate text-[11px] text-emerald-700 dark:text-emerald-300">
            {{ peerLabel(primaryCall) }}
          </span>
        </span>
      </button>

      <button
        type="button"
        class="rounded-md border border-emerald-200 bg-white px-2 py-1 text-xs font-medium text-emerald-800 hover:bg-emerald-100 disabled:cursor-not-allowed disabled:opacity-50 dark:border-emerald-800 dark:bg-slate-900 dark:text-emerald-200 dark:hover:bg-emerald-900/60"
        :disabled="busy"
        title="Reexibir chamada"
        @click="restore"
      >
        Exibir
      </button>
      <button
        type="button"
        class="rounded-md bg-red-600 px-2 py-1 text-xs font-semibold text-white hover:bg-red-700 disabled:cursor-not-allowed disabled:opacity-50"
        :disabled="busy"
        :title="compactActionLabel + ' chamada'"
        @click="compactEnd"
      >
        {{ compactActionLabel }}
      </button>
    </div>

    <div class="relative shrink-0">
      <hub-button
        v-tooltip="hasIncomingCall ? 'Chamada WhatsApp recebida' : 'Chamada WhatsApp'"
        variant="clear"
        color-scheme="secondary"
        icon="call"
        @click="toggle"
      />
      <span
        v-if="hasIncomingCall"
        class="pointer-events-none absolute right-0 top-0 h-2.5 w-2.5 animate-pulse rounded-full bg-red-500 ring-2 ring-white dark:ring-slate-900"
      />
    </div>

    <div
      v-if="open"
      class="fixed inset-0 z-50 flex items-center justify-center bg-slate-950/45 p-4 backdrop-blur-[1px]"
      @click.self="close"
    >
      <div
        class="w-full max-w-xl overflow-hidden rounded-2xl border border-emerald-200 bg-white shadow-2xl ring-1 ring-emerald-500/10 dark:border-emerald-900 dark:bg-slate-900"
      >
        <div class="flex items-center justify-between gap-3 bg-emerald-600 px-5 py-4 text-white dark:bg-emerald-700">
          <div class="flex min-w-0 items-center gap-3">
            <div
              class="flex h-10 w-10 shrink-0 items-center justify-center rounded-full bg-white/15 text-xl ring-1 ring-white/20"
              aria-hidden="true"
            >
              ☎
            </div>
            <div class="min-w-0">
              <h3 class="m-0 truncate text-lg font-semibold text-white">
                Chamada WhatsApp
              </h3>
              <p class="m-0 mt-0.5 truncate text-xs text-emerald-50/90">
                {{ primaryCall ? peerLabel(primaryCall) : 'Central de chamadas' }}
              </p>
            </div>
          </div>

          <div class="flex shrink-0 items-center gap-1.5">
            <button
              type="button"
              class="flex h-8 min-w-8 items-center justify-center rounded-md bg-white/10 px-2 text-sm font-semibold text-white hover:bg-white/20 focus:outline-none focus:ring-2 focus:ring-white/70"
              title="Minimizar chamada"
              aria-label="Minimizar chamada"
              @click="minimize"
            >
              —
            </button>
            <hub-button
              variant="clear"
              color-scheme="secondary"
              icon="dismiss"
              title="Fechar"
              @click="close"
            />
          </div>
        </div>

        <div class="p-5">
          <div
            v-if="error"
            class="mb-3 rounded-md bg-red-50 p-3 text-sm text-red-700 dark:bg-red-950/30 dark:text-red-300"
          >
            {{ error }}
          </div>
          <div
            v-if="mediaError"
            class="mb-3 rounded-md bg-yellow-50 p-3 text-sm text-yellow-700 dark:bg-yellow-950/30 dark:text-yellow-300"
          >
            {{ mediaError }}
          </div>
          <div
            v-if="feedback"
            class="mb-3 rounded-md bg-green-50 p-3 text-sm text-green-700 dark:bg-green-950/30 dark:text-green-300"
          >
            {{ feedback }}
          </div>

          <div
            class="mb-4 flex items-center justify-between rounded-lg border p-3"
            :class="
              mediaState === 'ready'
                ? 'border-emerald-200 bg-emerald-50/70 dark:border-emerald-800 dark:bg-emerald-950/30'
                : 'border-slate-200 bg-slate-50/60 dark:border-slate-700 dark:bg-slate-800/40'
            "
          >
            <div>
              <div class="text-sm font-medium text-slate-800 dark:text-slate-100">
                Áudio do navegador
              </div>
              <div
                class="text-xs"
                :class="
                  mediaState === 'ready'
                    ? 'text-emerald-700 dark:text-emerald-300'
                    : 'text-slate-500'
                "
              >
                {{ mediaStateLabel }}
              </div>
            </div>
            <span
              v-if="mediaCallId"
              class="max-w-[180px] truncate text-xs font-mono text-slate-500"
              :title="mediaCallId"
            >
              {{ mediaCallId }}
            </span>
          </div>

          <div
            v-if="loading"
            class="py-8 text-center text-sm text-slate-500"
          >
            Carregando chamadas…
          </div>
          <div v-else-if="activeCalls.length" class="mb-4 space-y-2">
            <div
              v-for="call in activeCalls"
              :key="callId(call)"
              class="rounded-xl border border-emerald-200 bg-emerald-50/40 p-3 dark:border-emerald-900 dark:bg-emerald-950/20"
            >
              <div class="flex flex-wrap items-center justify-between gap-3">
                <div class="min-w-0">
                  <div class="truncate text-sm font-semibold text-slate-900 dark:text-slate-100">
                    {{ peerLabel(call) }}
                  </div>
                  <div class="mt-0.5 text-xs font-medium text-emerald-700 dark:text-emerald-300">
                    {{ directionLabel(call) }} · {{ stateLabel(call) }}
                  </div>
                  <div
                    v-if="callDurationLabel(call)"
                    class="mt-2 font-mono text-lg font-semibold tabular-nums text-slate-800 dark:text-slate-100"
                  >
                    {{ callDurationLabel(call) }}
                  </div>
                </div>
                <div class="flex flex-wrap gap-2">
                  <hub-button
                    v-if="canAccept(call)"
                    size="small"
                    :disabled="busy"
                    @click="action(call, 'accept')"
                  >
                    Atender
                  </hub-button>
                  <hub-button
                    v-if="canReject(call)"
                    size="small"
                    variant="clear"
                    color-scheme="alert"
                    :disabled="busy"
                    @click="action(call, 'reject')"
                  >
                    Recusar
                  </hub-button>
                  <hub-button
                    v-if="mediaCallId === callId(call)"
                    size="small"
                    variant="clear"
                    :disabled="busy"
                    @click="action(call, 'mute')"
                  >
                    {{ call.muted ? 'Ativar mic' : 'Silenciar' }}
                  </hub-button>
                  <hub-button
                    size="small"
                    variant="clear"
                    color-scheme="alert"
                    :disabled="busy"
                    @click="action(call, 'end_call')"
                  >
                    Encerrar
                  </hub-button>
                </div>
              </div>
            </div>
          </div>
          <div
            v-else
            class="mb-4 rounded-lg border border-dashed border-slate-200 p-5 text-center text-sm text-slate-500 dark:border-slate-700"
          >
            Nenhuma chamada ativa nesta instância.
          </div>

          <div class="flex justify-end gap-2">
            <hub-button
              variant="clear"
              color-scheme="secondary"
              :disabled="busy"
              @click="loadCalls()"
            >
              Atualizar
            </hub-button>
            <hub-button
              icon="call"
              :disabled="busy || loading"
              @click="makeCall"
            >
              Ligar para este contato
            </hub-button>
          </div>
        </div>
      </div>
    </div>
  </div>
</template>
